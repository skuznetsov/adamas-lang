require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_enable_lazy_module_methods : Nil
    @lazy_module_methods = true
  end

  def __test_has_included_zero_arg_origin?(owner : String, method_name : String) : Bool
    !find_included_module_def_origin_for_owner(
      owner,
      method_name,
      0,
      false,
      respect_direct_declarations: false,
    ).nil?
  end

  def __test_owner_directly_declares_getter?(owner : String, method_name : String) : Bool
    owner_directly_declares_instance_getter?(owner, method_name)
  end

  def __test_direct_accessor_winner(owner : String, method_name : String) : Symbol?
    direct_accessor_winner(owner, method_name)
  end

  def __test_resolve_source_call_target(name : String, arg_type_names : Array(String)) : String?
    arg_types = arg_type_names.map { |type_name| type_ref_for_name(type_name) }
    target = resolve_call_target(CallResolutionInput.new(
      func_name: name,
      arg_count: arg_types.size,
      arg_types: arg_types,
      has_block: false,
      has_splat: false,
      has_named: false,
      named_names: nil,
    ))
    target.try(&.symbol_name)
  end
end

private def lower_generated_getter_include_fixture(source : String, lazy : Bool = false) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter.arena = arena

  macros = [] of Adamas::Compiler::Frontend::MacroDefNode
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  main = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::MacroDefNode
      macros << node
    when Adamas::Compiler::Frontend::ModuleNode
      modules << node
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    else
      main << root_id.index.to_u64
    end
  end

  macros.each { |node| converter.register_macro(node) }
  modules.each { |node| converter.register_module(node) }
  converter.__test_enable_lazy_module_methods if lazy
  classes.each { |node| converter.register_class(node) }
  classes.each { |node| converter.lower_class(node) } unless lazy
  modules.each { |node| converter.lower_module(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

private def getter_include_source(class_members : String, main : String) : String
  <<-CRYSTAL
    module IncludedSizeSource
      def size : Int32
        99
      end
    end

    class GetterSizeOwner(T)
      #{class_members}

      def initialize(@size : T)
      end
    end

    #{main}
  CRYSTAL
end

private def getter_include_hir_text(function : Adamas::HIR::Function) : String
  String.build { |io| function.to_s(io) }
end

describe "source getter precedence over included zero-argument methods" do
  it "publishes only the latest direct zero-argument Def body" do
    converter = lower_generated_getter_include_fixture(<<-CRYSTAL)
      class RepeatedDirectSizeOwner
        def size : Int32
          65
        end

        def size : Int32
          66
        end
      end

      RepeatedDirectSizeOwner.new.size
    CRYSTAL

    own = converter.module.function_by_name("RepeatedDirectSizeOwner#size")
    own.should_not be_nil
    text = getter_include_hir_text(own.not_nil!)
    text.should contain("literal 66")
    text.should_not contain("literal 65")
    converter.__test_direct_accessor_winner("RepeatedDirectSizeOwner", "size").should eq(:def)
  end

  {false, true}.each do |lazy|
    {false, true}.each do |getter_first|
      it "selects a generic receiver's direct getter (lazy=#{lazy}, getter_first=#{getter_first})" do
        members = if getter_first
                    "getter size : T\ninclude IncludedSizeSource"
                  else
                    "include IncludedSizeSource\ngetter size : T"
                  end
        converter = lower_generated_getter_include_fixture(
          getter_include_source(
            members,
            "GetterSizeOwner(Int32).new(65).size",
          ),
          lazy,
        )

        getter = converter.module.function_by_name("GetterSizeOwner(Int32)#size")
        getter.should_not be_nil
        text = getter_include_hir_text(getter.not_nil!)
        text.should contain("field_get")
        text.should contain("@size")
        text.should_not contain("literal 99")
        if lazy
          converter.__test_has_included_zero_arg_origin?("GetterSizeOwner(Int32)", "size").should be_false
        end
      end
    end
  end

  {false, true}.each do |lazy|
    it "keeps an included method when the receiver declares no getter (lazy=#{lazy})" do
      converter = lower_generated_getter_include_fixture(<<-CRYSTAL, lazy)
        module IncludedOnlySizeSource
          def size : Int32
            99
          end
        end

        class IncludedOnlySizeOwner
          include IncludedOnlySizeSource
        end

        IncludedOnlySizeOwner.new.size
      CRYSTAL

      included = converter.module.function_by_name("IncludedOnlySizeOwner#size")
      included.should_not be_nil
      converter.__test_has_included_zero_arg_origin?("IncludedOnlySizeOwner", "size").should be_true
      text = getter_include_hir_text(included.not_nil!)
      text.should contain("literal 99")
      text.should_not contain("field_get")
    end
  end

  {false, true}.each do |lazy|
    it "preserves an explicit receiver method over its generated getter and include (lazy=#{lazy})" do
      members = <<-CRYSTAL
        include IncludedSizeSource
        getter size : Int32
        def size : Int32
          65
        end
      CRYSTAL
      converter = lower_generated_getter_include_fixture(
        getter_include_source(members, "GetterSizeOwner(Int32).new(7).size"),
        lazy,
      )

      own = converter.module.function_by_name("GetterSizeOwner(Int32)#size")
      own.should_not be_nil
      text = getter_include_hir_text(own.not_nil!)
      text.should contain("literal 65")
      text.should_not contain("literal 99")
      text.should_not contain("field_get")
      converter.__test_direct_accessor_winner("GetterSizeOwner(Int32)", "size").should eq(:def)
    end

    it "lets a later getter replace an earlier same-named Def (lazy=#{lazy})" do
      members = <<-CRYSTAL
        include IncludedSizeSource
        def size : Int32
          65
        end
        getter size : Int32
      CRYSTAL
      converter = lower_generated_getter_include_fixture(
        getter_include_source(members, "GetterSizeOwner(Int32).new(66).size"),
        lazy,
      )

      getter = converter.module.function_by_name("GetterSizeOwner(Int32)#size")
      getter.should_not be_nil
      text = getter_include_hir_text(getter.not_nil!)
      text.should contain("field_get")
      text.should contain("@size")
      text.should_not contain("literal 65")
      text.should_not contain("literal 99")
      converter.__test_direct_accessor_winner("GetterSizeOwner(Int32)", "size").should eq(:getter)
    end
  end

  it "records a later getter expanded from the receiver's macro context" do
    converter = lower_generated_getter_include_fixture(<<-CRYSTAL)
      macro add_source_size_getter
        getter size : Int32
      end

      module MacroIncludedSizeSource
        def size : Int32
          99
        end
      end

      class MacroGetterSizeOwner
        include MacroIncludedSizeSource

        def initialize(@size : Int32)
        end

        def size : Int32
          65
        end

        add_source_size_getter()
      end

      MacroGetterSizeOwner.new(65).size
    CRYSTAL

    getter = converter.module.function_by_name("MacroGetterSizeOwner#size")
    getter.should_not be_nil
    text = getter_include_hir_text(getter.not_nil!)
    text.should contain("field_get")
    text.should contain("@size")
    text.should_not contain("literal 65")
    text.should_not contain("literal 99")
    converter.__test_direct_accessor_winner("MacroGetterSizeOwner", "size").should eq(:getter)
  end

  it "lets a later Def replace an earlier getter expanded from the receiver's macro context" do
    converter = lower_generated_getter_include_fixture(<<-CRYSTAL)
      macro add_source_size_getter
        getter size : Int32
      end

      module MacroIncludedSizeSource
        def size : Int32
          99
        end
      end

      class MacroGetterSizeOwner
        include MacroIncludedSizeSource

        def initialize(@size : Int32)
        end

        add_source_size_getter()

        def size : Int32
          65
        end
      end

      MacroGetterSizeOwner.new(66).size
    CRYSTAL

    own = converter.module.function_by_name("MacroGetterSizeOwner#size")
    own.should_not be_nil
    text = getter_include_hir_text(own.not_nil!)
    text.should contain("literal 65")
    text.should_not contain("field_get")
    text.should_not contain("literal 99")
    converter.__test_direct_accessor_winner("MacroGetterSizeOwner", "size").should eq(:def)
  end

  {false, true}.each do |lazy|
    it "records a later optional-argument Def as the getter-name winner (lazy=#{lazy})" do
      converter = lower_generated_getter_include_fixture(<<-CRYSTAL, lazy)
        class GetterDefaultSizeOwner
          def initialize(@size : Int32)
          end

          getter size : Int32

          def size(extra : Int32 = 0) : Int32
            65
          end
        end

        GetterDefaultSizeOwner.new(66).size
      CRYSTAL

      selected = converter.__test_resolve_source_call_target("GetterDefaultSizeOwner#size", [] of String)
      selected.should_not be_nil
      own = converter.module.function_by_name(selected.not_nil!)
      own.should_not be_nil
      text = getter_include_hir_text(own.not_nil!)
      text.should contain("literal 65")
      text.should_not contain("field_get")
      converter.__test_direct_accessor_winner("GetterDefaultSizeOwner", "size").should eq(:def)
      converter.__test_resolve_source_call_target("GetterDefaultSizeOwner#size", [] of String).should_not be_nil
      converter.__test_resolve_source_call_target("GetterDefaultSizeOwner#size", ["Int32"]).should_not be_nil
    end

    it "lets a getter after an optional-argument Def own the zero-argument shape (lazy=#{lazy})" do
      converter = lower_generated_getter_include_fixture(<<-CRYSTAL, lazy)
        class DefaultGetterSizeOwner
          def initialize(@size : Int32)
          end

          def size(extra : Int32 = 0) : Int32
            65
          end

          getter size : Int32
        end

        DefaultGetterSizeOwner.new(66).size
      CRYSTAL

      getter = converter.module.function_by_name("DefaultGetterSizeOwner#size")
      getter.should_not be_nil
      text = getter_include_hir_text(getter.not_nil!)
      text.should contain("field_get")
      text.should contain("@size")
      text.should_not contain("literal 65")
      converter.__test_direct_accessor_winner("DefaultGetterSizeOwner", "size").should eq(:getter)
      converter.__test_resolve_source_call_target("DefaultGetterSizeOwner#size", ["Int32"]).should be_nil
    end
  end

  it "retains a separate required-argument Def overload beside a getter" do
    converter = lower_generated_getter_include_fixture(<<-CRYSTAL)
      class RequiredGetterSizeOwner
        def initialize(@size : Int32)
        end

        getter size : Int32

        def size(extra : Int32) : Int32
          65
        end
      end

      RequiredGetterSizeOwner.new(66).size
    CRYSTAL

    getter = converter.module.function_by_name("RequiredGetterSizeOwner#size")
    getter.should_not be_nil
    getter_include_hir_text(getter.not_nil!).should contain("field_get")
    converter.__test_resolve_source_call_target("RequiredGetterSizeOwner#size", ["Int32"]).should_not be_nil
  end
end
