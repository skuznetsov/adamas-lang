require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_nested_yield_under_caller_scope
    old_def = @current_def_node
    old_method = @current_method
    old_class = @current_class
    @current_def_node = @function_defs["HandleContextOwner#caller$Int32"]
    @current_method = "caller"
    @current_class = "HandleContextOwner"
    begin
      __test_nested_yield_with_ambient("HandleContextOwner#each_child", "HandleContextOwner#each_child$String_block", "HandleContextOwner", nil)
    ensure
      @current_def_node = old_def
      @current_method = old_method
      @current_class = old_class
    end
  end
  def __test_nested_yield_types(
    base_method_name : String,
    mangled_method_name : String,
    receiver_name : String,
    arg_type_names : Array(String),
  ) : Array(String)?
    receiver_type = type_ref_for_name(receiver_name)
    arg_types = arg_type_names.map { |name| type_ref_for_name(name) }
    block_param_types_for_call(
      mangled_method_name,
      base_method_name,
      receiver_type,
      arg_types,
    ).try(&.map { |type_ref| get_type_name_from_ref(type_ref) })
  end

  def __test_nested_yield_with_ambient(
    base_method_name : String,
    mangled_method_name : String,
    receiver_name : String,
    ambient_name : String?,
  ) : Array(String)?
    old_locals = @current_typeof_locals
    old_names = @current_typeof_local_names
    @current_typeof_locals = {} of String => Adamas::HIR::TypeRef
    @current_typeof_local_names = {} of String => String
    if ambient_name
      @current_typeof_locals.not_nil!["entry"] = type_ref_for_name(ambient_name)
      @current_typeof_local_names.not_nil!["entry"] = "entry"
    end
    @infer_type_cache_version += 1
    begin
      __test_nested_yield_types(base_method_name, mangled_method_name, receiver_name, ["String"])
    ensure
      @current_typeof_locals = old_locals
      @current_typeof_local_names = old_names
      @infer_type_cache_version += 1
    end
  end
end

def parse_nested_yield_probe(code : String) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?
  {result.arena, result.roots}
end

def lower_nested_yield_probe(code : String) : Adamas::HIR::AstToHir
  arena, roots = parse_nested_yield_probe(code)
  converter = Adamas::HIR::AstToHir.new(arena)
  converter.arena = arena
  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  roots.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    end
  end
  type_names = (module_nodes.map { |node| String.new(node.name) } + class_nodes.map { |node| String.new(node.name) })
  converter.seed_top_level_type_names(type_names)
  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  def_nodes.each { |node| converter.register_function(node) }
  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter
end

source = <<-CRYSTAL
  class HandleContextOwner
    def caller(dir : Int32)
      dir
    end
    struct Entry
      getter name : Int32
      def initialize(@name : Int32)
      end
    end
    class Handle
      def self.open(path : String, & : self ->)
        yield new
      end
      def next_entry : Entry?
        Entry.new(73)
      end
    end
    def read_entry(dir)
      return unless dir
      dir.next_entry
    end
    def each_child(path : String, &)
      Handle.open(path) do |dir|
        while entry = read_entry(dir)
          next if entry.name == 0
          yield entry
        end
      end
    rescue Exception
    end
  end
CRYSTAL


describe "Nested yield callsite inference" do
  it "infers a nested reader result without importing a same-name caller local" do
    converter = lower_nested_yield_probe(source)
    [nil, "Int32", "Pointer"].each do |ambient|
      converter.__test_nested_yield_with_ambient("HandleContextOwner#each_child", "HandleContextOwner#each_child$String_block", "HandleContextOwner", ambient).should eq(["HandleContextOwner::Entry"])
    end
  end

  it "retains typed reader and nested block receiver controls" do
    {"yield entry" => "HandleContextOwner::Entry", "yield dir" => "HandleContextOwner::Handle"}.each do |yield_text, expected|
      code = source.gsub("def read_entry(dir)", "def read_entry(dir : HandleContextOwner::Handle) : HandleContextOwner::Entry?").gsub("yield entry", yield_text)
      converter = lower_nested_yield_probe(code)
      converter.__test_nested_yield_with_ambient("HandleContextOwner#each_child", "HandleContextOwner#each_child$String_block", "HandleContextOwner", "Pointer").should eq([expected])
    end
  end

  it "does not share an untyped return across concrete callsites" do
    converter = lower_nested_yield_probe(<<-CRYSTAL)
      class ForwardOwner
        def forward(value, &)
          yield identity(value)
        end
        def identity(value)
          value
        end
      end
    CRYSTAL
    ["Int32", "String", "Int32"].each do |name|
      converter.__test_nested_yield_types("ForwardOwner#forward", "ForwardOwner#forward", "ForwardOwner", [name]).should eq([name])
    end
  end

  it "terminates recursive return inference without inventing Entry" do
    converter = lower_nested_yield_probe(source.gsub("dir.next_entry", "read_entry(dir)"))
    result = converter.__test_nested_yield_with_ambient("HandleContextOwner#each_child", "HandleContextOwner#each_child$String_block", "HandleContextOwner", "Pointer")
    result.should_not eq(["HandleContextOwner::Entry"])
    result.should_not eq(["Pointer"])
  end
  it "keeps inherited method constants in their declaration namespace" do
    converter = lower_nested_yield_probe(<<-CRYSTAL)
      class ParentOwner
        class Token
        end
        def forward(value, &)
          yield read(value)
        end
        def read(value)
          Token.new
        end
      end
      class ChildOwner < ParentOwner
        class Token
        end
      end
    CRYSTAL
    converter.__test_nested_yield_types("ParentOwner#forward", "ParentOwner#forward", "ChildOwner", ["Int32"]).should eq(["ParentOwner::Token"])
  end

  it "does not inherit a caller formal parameter annotation" do
    lower_nested_yield_probe(source).__test_nested_yield_under_caller_scope.should eq(["HandleContextOwner::Entry"])
  end

  it "infers a nested open with a nullable path and fallback" do
    code = source.gsub("def each_child(path : String, &)", "def each_child(path, &)").gsub("Handle.open(path)", "Handle.open(path || \"test\")")
    converter = lower_nested_yield_probe(code)
    converter.__test_nested_yield_types("HandleContextOwner#each_child", "HandleContextOwner#each_child", "HandleContextOwner", ["Nil | String"]).should eq(["HandleContextOwner::Entry"])
  end

  it "infers a reader using a typed module method and instance-variable argument" do
    code = source.gsub("class Handle\n", "class Handle\n      @raw : Int32 = 73\n      def path : String; \"test\"; end\n")
    code = code.gsub("dir.next_entry", "EntrySystem.next_entry(dir.@raw, dir.path)")
    code += "\n"
    code += <<-CRYSTAL
      module EntrySystem
        struct Entry
          def name : Int32
            73
          end
        end
        def self.next_entry(raw, path) : Entry?
          Entry.new
        end
      end
    CRYSTAL
    {
      "original" => code,
      "literal_args" => code.gsub("dir.@raw, dir.path", "73, \"test\""),
      "qualified_return" => code.gsub(": Entry?", ": EntrySystem::Entry?"),
      "typed_args" => code.gsub("def self.next_entry(raw, path)", "def self.next_entry(raw : Int32, path : String)"),
      "competing_overloads" => code.gsub("def self.next_entry(raw, path)", "def self.next_entry(raw : Int32, path : String)").sub("module EntrySystem", "module EntrySystem\n  def self.next_entry(raw : String, path : String) : String; raw; end"),
      "direct_yield" => code.gsub("yield entry", "yield EntrySystem.next_entry(73, \"test\")"),
    }.each do |label, candidate|
      converter = lower_nested_yield_probe(candidate)
      result = converter.__test_nested_yield_types("HandleContextOwner#each_child", "HandleContextOwner#each_child", "HandleContextOwner", ["String"])
      expected = label == "direct_yield" ? ["Nil | EntrySystem::Entry"] : ["EntrySystem::Entry"]
      result.should eq(expected)
    end
  end

  it "does not select a static overload with an unknown positional argument" do
    converter = lower_nested_yield_probe(<<-CRYSTAL)
      module EntrySystem
        def self.select(value : Int32, label : String) : Int32
          value
        end
        def self.select(value : String, label : String) : String
          value
        end
      end
      class ForwardOwner
        def forward(value, &)
          yield EntrySystem.select(value, "test")
        end
      end
    CRYSTAL
    ["Int32", "String", "Pointer", "Int32"].each do |name|
      result = converter.__test_nested_yield_types("ForwardOwner#forward", "ForwardOwner#forward", "ForwardOwner", [name])
      result.should eq(name == "Pointer" ? nil : [name])
    end
  end

  it "retains returns from nested calls with different argument specializations" do
    converter = lower_nested_yield_probe(<<-CRYSTAL)
      class ReentryOwner
        def read(value)
          return read("nested") if value == 1
          value
        end
        def forward(value, &)
          yield read(value)
        end
      end
    CRYSTAL
    converter.__test_nested_yield_types("ReentryOwner#forward", "ReentryOwner#forward", "ReentryOwner", ["Int32"]).should eq(["Int32 | String"])
  end

  it "includes named argument types in the active inference specialization" do
    converter = lower_nested_yield_probe(<<-CRYSTAL)
      class ReentryOwner
        def read(tag, value = 0)
          return read(tag, value: "nested") if value == 1
          value
        end
        def forward(value, &)
          yield read(0, value: value)
        end
      end
    CRYSTAL
    converter.__test_nested_yield_types("ReentryOwner#forward", "ReentryOwner#forward", "ReentryOwner", ["Int32"]).should eq(["Int32 | String"])
  end

end
