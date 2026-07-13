require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_array_identity_lower_function_if_needed(name : String) : Nil
    lower_function_if_needed(name)
  end

  def __test_shadow_function_def(target : String, source : String) : Nil
    definition = @function_defs[source]
    arena = @function_def_arenas[source]
    set_function_def_entry(target, definition)
    set_function_def_arena(target, arena)
  end

  def __test_remember_zero_arg_callsite(name : String) : Nil
    remember_callsite_arg_types(name, [] of Adamas::HIR::TypeRef)
  end
end

private def array_identity_parse(code : String) : {Adamas::Compiler::Frontend::ArenaLike, Array(Adamas::Compiler::Frontend::ExprId)}
  lexer = Adamas::Compiler::Frontend::Lexer.new(code)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  result = parser.parse_program
  {result.arena, result.roots}
end

private def prepare_array_identity_program(code : String) : {Adamas::HIR::AstToHir, Array(Adamas::Compiler::Frontend::DefNode)}
  arena, exprs = array_identity_parse(code)
  converter = Adamas::HIR::AstToHir.new(arena)
  converter.arena = arena

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  defs = [] of Adamas::Compiler::Frontend::DefNode
  exprs.each do |expr_id|
    case node = arena[expr_id]
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    when Adamas::Compiler::Frontend::DefNode
      defs << node
    end
  end

  classes.each { |node| converter.register_class(node) }
  defs.each { |node| converter.register_function(node) }
  classes.each { |node| converter.lower_class(node) }
  {converter, defs}
end

private def array_identity_hir_text(function : Adamas::HIR::Function) : String
  String.build { |io| function.to_s(io) }
end

describe "generic Array constructor identity" do
  it "keeps zero-arg callsites and allocator bodies specialized to the element type" do
    converter, defs = prepare_array_identity_program(<<-CRYSTAL)
      class Array(T)
        @size : Int32

        def initialize
          @size = 0
        end

        def initialize(initial_capacity : Int32)
        end

        def initialize(size : Int32, value : T)
        end

        def self.new(size : Int32, & : Int32 -> T)
          Array(T).new(size)
        end
      end

      struct ProbeTypeRef
        def initialize(@id : UInt32)
        end
      end

      def string_array
        Array(String).new
      end

      def probe
        Array(ProbeTypeRef).new
      end
    CRYSTAL

    string_array_def = defs.find { |definition| String.new(definition.name) == "string_array" }
    converter.lower_def(string_array_def.not_nil!)
    converter.__test_shadow_function_def("Array(ProbeTypeRef).new", "Array.new$Int32_block")
    converter.__test_remember_zero_arg_callsite("Array(ProbeTypeRef).new")
    probe_def = defs.find { |definition| String.new(definition.name) == "probe" }
    converter.lower_def(probe_def.not_nil!)

    probe = converter.module.functions.find { |function| function.name.starts_with?("probe") }
    probe.should_not be_nil
    call = probe.not_nil!.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Adamas::HIR::Call) && instruction.as(Adamas::HIR::Call).method_name.ends_with?(".new")
    end
    call.should_not be_nil
    call = call.not_nil!.as(Adamas::HIR::Call)
    call.method_name.should eq("Array(ProbeTypeRef).new")
    call.args.size.should eq(0)

    converter.__test_array_identity_lower_function_if_needed("Array(ProbeTypeRef).new")
    allocator = converter.module.functions.find { |function| function.name == "Array(ProbeTypeRef).new" }
    allocator.should_not be_nil
    allocator.not_nil!.params.size.should eq(0)
    allocator_text = array_identity_hir_text(allocator.not_nil!)
    allocator_text.should contain("Array(ProbeTypeRef)")
    allocator_text.should_not contain("Array(String)")
  end
end
