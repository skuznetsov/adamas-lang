require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_macro_yield_type_name(type_ref : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type_ref)
  end
end

private def macro_yield_parse(
  code : String,
) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

private def lower_macro_yield_program(code : String) : Adamas::HIR::AstToHir
  arena, exprs = macro_yield_parse(code)
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => code},
  )
  converter.arena = arena

  enum_nodes = [] of Adamas::Compiler::Frontend::EnumNode
  module_nodes = [] of Adamas::Compiler::Frontend::ModuleNode
  class_nodes = [] of Adamas::Compiler::Frontend::ClassNode
  def_nodes = [] of Adamas::Compiler::Frontend::DefNode
  alias_nodes = [] of Adamas::Compiler::Frontend::AliasNode
  main_exprs = [] of UInt64

  exprs.each do |expr_id|
    node = arena[expr_id]
    case node
    when Adamas::Compiler::Frontend::EnumNode
      enum_nodes << node
    when Adamas::Compiler::Frontend::ModuleNode
      module_nodes << node
    when Adamas::Compiler::Frontend::ClassNode
      class_nodes << node
    when Adamas::Compiler::Frontend::DefNode
      def_nodes << node
    when Adamas::Compiler::Frontend::AliasNode
      alias_nodes << node
    when Adamas::Compiler::Frontend::CallNode
      main_exprs << expr_id.index.to_u64
    end
  end

  enum_nodes.each { |node| converter.register_enum(node) }
  module_nodes.each { |node| converter.register_module(node) }
  class_nodes.each { |node| converter.register_class(node) }
  alias_nodes.each { |node| converter.register_alias(node) }
  def_nodes.each { |node| converter.register_function(node) }

  module_nodes.each { |node| converter.lower_module(node) }
  class_nodes.each { |node| converter.lower_class(node) }
  def_nodes.each { |node| converter.lower_def(node) }
  converter.lower_main(main_exprs) unless main_exprs.empty?
  converter
end

private def with_inline_yield_disabled(& : -> Adamas::HIR::AstToHir)
  previous = ENV["ADAMAS_DISABLE_INLINE_YIELD"]?
  ENV["ADAMAS_DISABLE_INLINE_YIELD"] = "1"
  yield
ensure
  if previous
    ENV["ADAMAS_DISABLE_INLINE_YIELD"] = previous
  else
    ENV.delete("ADAMAS_DISABLE_INLINE_YIELD")
  end
end

private def macro_yield_block_proc(
  converter : Adamas::HIR::AstToHir,
  names : Array(String),
) : Adamas::HIR::Function
  matches = converter.module.functions.select do |function|
    function.name.starts_with?("__crystal_block_proc_") &&
      function.params.map(&.name) == names
  end
  raise "expected one block proc #{names.inspect}, got #{matches.map(&.name).inspect}" unless matches.size == 1
  matches.first
end

private def macro_yield_type_names(
  converter : Adamas::HIR::AstToHir,
  function : Adamas::HIR::Function,
) : Array(String)
  function.params.map { |param| converter.__test_macro_yield_type_name(param.type) }
end

private def untyped_tuple_reduce_source : String
  <<-CRYSTAL
    module Enumerable(T)
    end

    class Path
      def initialize(@value : Int32)
      end

      def join(part : Int32) : Path
        self
      end

      def join(parts : Tuple(Int32, Int32)) : Path
        parts.reduce(self) { |path, part| path.join(part) }
      end
    end

    struct Tuple
      include Enumerable(Union(*T))

      def reduce(memo, &)
        {% for i in 0...T.size %}
          memo = yield memo, self[{{ i }}]
        {% end %}
        memo
      end
    end

    class Thread
      def join : Nil
        nil
      end
    end

    Path.new(39).join({1, 2})
  CRYSTAL
end

private def manual_tuple_reduce_source : String
  <<-CRYSTAL
    module Enumerable(T)
    end

    class Path
      def initialize(@value : Int32)
      end

      def join(part : Int32) : Path
        self
      end

      def join(parts : Tuple(Int32, Int32)) : Path
        parts.reduce_manual(self) { |path, part| path.join(part) }
      end
    end

    struct Tuple
      include Enumerable(Union(*T))

      def reduce_manual(memo, &)
        memo = yield memo, self[0]
        memo = yield memo, self[1]
        memo
      end
    end

    Path.new(39).join({1, 2})
  CRYSTAL
end

private def ordinary_yield_source : String
  <<-CRYSTAL
    class Path
      def initialize(@value : Int32)
      end

      def join(part : Int32) : Path
        self
      end

      def consume(&)
        yield self, 1
      end

      def probe : Path
        consume { |path, part| path.join(part) }
      end
    end

    Path.new(39).probe
  CRYSTAL
end

private def heterogeneous_tuple_reduce_source : String
  <<-CRYSTAL
    module Enumerable(T)
    end

    class Path
      def initialize(@value : Int32)
      end

      def join(part : Int32) : Path
        self
      end

      def join(part : String) : Path
        self
      end

      def join(parts : Tuple(Int32, String)) : Path
        parts.reduce(self) { |path, part| path.join(part) }
      end
    end

    struct Tuple
      include Enumerable(Union(*T))

      def reduce(memo, &)
        {% for i in 0...T.size %}
          memo = yield memo, self[{{ i }}]
        {% end %}
        memo
      end
    end

    class Thread
      def join : Nil
        nil
      end
    end

    Path.new(39).join({1, "two"})
  CRYSTAL
end

private def mixed_tuple_reduce_source : String
  <<-CRYSTAL
    module Enumerable(T)
    end

    class Path
      def initialize(@value : Int32)
      end

      def join(part : Int32) : Path
        self
      end

      def join(part : String) : Path
        self
      end

      def join(parts : Tuple(Int32, String)) : Path
        parts.reduce_mixed(self) { |path, part| path.join(part) }
      end
    end

    struct Tuple
      include Enumerable(Union(*T))

      def reduce_mixed(memo, &)
        yield memo, 0
        {% for i in 0...T.size %}
          memo = yield memo, self[{{ i }}]
        {% end %}
        memo
      end
    end

    class Thread
      def join : Nil
        nil
      end
    end

    Path.new(39).join({1, "two"})
  CRYSTAL
end

private def macro_local_alias_source : String
  <<-CRYSTAL
    module Enumerable(T)
    end

    class Path
      def initialize(@value : Int32)
      end

      def join(part : Int32) : Path
        self
      end

      def join(parts : Tuple(Int32, Int32)) : Path
        parts.reduce_local_alias(self) { |path, part| path.join(part) }
      end
    end

    struct Tuple
      include Enumerable(Union(*T))

      def reduce_local_alias(memo, &)
        item = self[0]
        {% for i in 0...T.size %}
          memo = yield memo, item
        {% end %}
        memo
      end
    end

    class Thread
      def join : Nil
        nil
      end
    end

    Path.new(39).join({1, 2})
  CRYSTAL
end

describe "macro-generated yield parameter inference" do
  it "recovers the accumulator and every yielded argument for Tuple#reduce" do
    converter = with_inline_yield_disabled { lower_macro_yield_program(untyped_tuple_reduce_source) }
    proc_func = macro_yield_block_proc(converter, ["path", "part"])

    macro_yield_type_names(converter, proc_func).should eq(["Path", "Int32"])
  end

  it "keeps manually unrolled yields as a positive control" do
    converter = with_inline_yield_disabled { lower_macro_yield_program(manual_tuple_reduce_source) }
    proc_func = macro_yield_block_proc(converter, ["path", "part"])

    macro_yield_type_names(converter, proc_func).should eq(["Path", "Int32"])
  end

  it "keeps an ordinary yield control typed" do
    converter = with_inline_yield_disabled { lower_macro_yield_program(ordinary_yield_source) }
    proc_func = macro_yield_block_proc(converter, ["path", "part"])

    macro_yield_type_names(converter, proc_func).should eq(["Path", "Int32"])
  end

  it "merges all yielded positions for a heterogeneous Tuple#reduce" do
    converter = with_inline_yield_disabled { lower_macro_yield_program(heterogeneous_tuple_reduce_source) }
    proc_func = macro_yield_block_proc(converter, ["path", "part"])

    macro_yield_type_names(converter, proc_func).should eq(["Path", "Int32 | String"])
  end

  it "merges positional types from ordinary and macro-generated yields" do
    converter = with_inline_yield_disabled { lower_macro_yield_program(mixed_tuple_reduce_source) }
    proc_func = macro_yield_block_proc(converter, ["path", "part"])

    macro_yield_type_names(converter, proc_func).should eq(["Path", "Int32 | String"])
  end

  it "carries a method-local alias into a macro-generated yield" do
    converter = with_inline_yield_disabled { lower_macro_yield_program(macro_local_alias_source) }
    proc_func = macro_yield_block_proc(converter, ["path", "part"])

    macro_yield_type_names(converter, proc_func).should eq(["Path", "Int32"])
  end
end
