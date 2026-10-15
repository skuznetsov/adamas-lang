require "../spec_helper"
require "../semantic_cli_helpers"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/cli"

include SemanticCliSpecHelpers

class Adamas::HIR::AstToHir
  def __test_suffix_has_block_flag?(suffix : String) : Bool
    suffix_has_block_flag?(suffix)
  end

  def __test_named_suffix_runtime_shape(suffix : String)
    {
      parse_types_from_suffix(suffix),
      parse_type_ids_from_suffix(suffix),
      suffix_part_count(suffix),
      strip_mangled_suffix_flags(suffix),
    }
  end

  def __test_function_full_name_for_def(
    base_name : String,
    param_types : Array(Adamas::HIR::TypeRef),
    def_node : Adamas::Compiler::Frontend::DefNode,
  ) : String
    function_full_name_for_def(base_name, param_types, def_node.params, false)
  end
end

private def named_block_suffix_hir(source : String) : String
  with_temp_shadow_project({"main.cr" => source}) do |dir|
    target = File.join(dir, "main")
    errors = IO::Memory.new
    status = Adamas::Compiler::CLI.new([
      File.join(dir, "main.cr"), "--no-prelude", "--emit", "hir",
      "--no-link", "--no-llvm-cache", "-o", target,
    ]).run(out_io: IO::Memory.new, err_io: errors)

    status.should eq(0), errors.to_s
    File.read("#{target}.hir")
  end
end

private def named_block_function_section(hir : String) : String?
  lines = [] of String
  in_function = false
  found = false
  hir.each_line do |line|
    if line.starts_with?("func @")
      if in_function
        break
      end
      in_function = line.starts_with?("func @NamedBlockSuffixProbe#f$") && line.includes?("block_id")
      found ||= in_function
    end
    lines << line if in_function
  end
  found ? lines.join : nil
end

private def forall_block_def_and_converter : {
  Adamas::HIR::AstToHir,
  Adamas::Compiler::Frontend::DefNode,
}
  source = <<-CRYSTAL
    class T
    end
    class BlockSuffixForallExprId
    end
    class NamedBlockSuffixForallProbe
      def apply(value : T,
                *,
                block_id : BlockSuffixForallExprId? = nil,
                &block : T -> T) : T forall T
        yield value
      end
    end
  CRYSTAL
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  ).parse_program
  class_node = parsed.roots.compact_map do |root_id|
    parsed.arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
  end.find { |node| String.new(node.name) == "NamedBlockSuffixForallProbe" }.not_nil!
  def_node = class_node.body.not_nil!.compact_map do |member_id|
    parsed.arena[member_id].as?(Adamas::Compiler::Frontend::DefNode)
  end.first.not_nil!

  converter = Adamas::HIR::AstToHir.new(
    parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source},
  )
  {converter, def_node}
end

describe "named-only labels and mangled block flags" do
  it "excludes source labels from runtime type decoding and arity" do
    arena = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("")
    ).parse_program.arena
    converter = Adamas::HIR::AstToHir.new(arena)

    [
      "Int32_Bool_block_named_4_name_11_same_thread",
      "Int32_Bool_block_named_14_block_id_super_super",
    ].each do |suffix|
      types, type_ids, parts, stripped = converter.__test_named_suffix_runtime_shape(suffix)
      types.should eq([Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::BOOL])
      type_ids.should eq([Adamas::HIR::TypeRef::INT32.id, Adamas::HIR::TypeRef::BOOL.id])
      parts.should eq(3)
      stripped.should eq("Int32_Bool")
    end
  end

  it "does not treat block-like named labels as block ABI markers" do
    arena = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("")
    ).parse_program.arena
    converter = Adamas::HIR::AstToHir.new(arena)

    [
      "Int32_Nil_named_8_block_id",
      "Int32_Nil_named_10_named_args_8_block_id_31_preserve_unresolved_expressions",
      "Int32_Nil_named_5_block",
      "Int32_Nil_named_11_save_block_id",
      "Int32_Nil_named_7_block_id",
      # The last token is part of the length-prefixed source label. A plain
      # suffix check must not strip it as the super dispatch tag.
      "Int32_Nil_named_14_block_id_super",
      # The source label `block_super` must remain payload when there is no
      # producer-added super dispatch tag.
      "Int32_named_11_block_super",
      # The final `_super` is a real dispatch tag here, but the decoded label
      # still is not an ABI block marker.
      "Int32_Nil_named_14_block_id_super_super",
      # A malformed tail must not be accepted just because `_super` is a
      # valid final dispatch tag.
      "Int32_block_named_8_block_id_superfluous_super",
    ].each do |suffix|
      converter.__test_suffix_has_block_flag?(suffix).should be_false
    end
  end

  it "keeps explicit block markers with typed and forall suffixes" do
    arena = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("")
    ).parse_program.arena
    converter = Adamas::HIR::AstToHir.new(arena)

    [
      "block",
      "Int32_block",
      "Array(Int32)_block",
      "T_block",
      "Array(T)_block_named_8_block_id",
      "T_block$arity1_splat",
      "T$arity2_block",
      # lower_super appends `_super` after the fully resolved method key.
      "Int32_block_super",
      "Int32_block_named_8_block_id_super",
      # Here `block_super` is payload and the final `_super` is the producer
      # tag; preserve the genuine block marker before the named tail.
      "Int32_block_named_11_block_super_super",
      "Int32_block_named_14_block_id_super_super",
      "T_block$arity1_splat_named_8_block_id_super",
    ].each do |suffix|
      converter.__test_suffix_has_block_flag?(suffix).should be_true
    end
  end

  it "preserves the actual typed forall block marker before its block_id label" do
    converter, def_node = forall_block_def_and_converter
    full_name = converter.__test_function_full_name_for_def(
      "NamedBlockSuffixForallProbe#apply",
      [Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::NIL],
      def_node,
    )

    full_name.should contain("_block_named_8_block_id")
    suffix = full_name.byte_slice("NamedBlockSuffixForallProbe#apply$".bytesize)
    converter.__test_suffix_has_block_flag?(suffix).should be_true

    # Match lower_super's producer exactly: it appends `_super` to the
    # resolved full method name, after the encoded named-only tail.
    super_tagged_suffix = "#{suffix}_super"
    converter.__test_suffix_has_block_flag?(super_tagged_suffix).should be_true
  end

  it "does not infer a block marker from the actual super dispatch tag alone" do
    hir = named_block_suffix_hir(<<-CRYSTAL)
      class SuperBlockBase
        def apply(value : Int32,
                  *,
                  block_id : Int32? = nil,
                  &block : Int32 -> Int32) : Int32
          yield value
        end
      end

      class SuperBlockChild < SuperBlockBase
        def apply(value : Int32,
                  *,
                  block_id : Int32? = nil,
                  &block : Int32 -> Int32) : Int32
          super
        end
      end

      SuperBlockChild.new.apply(8, block_id: nil) { |item| item + 2 }
      CRYSTAL

    hir.should contain("SuperBlockBase#apply$")
    target = hir.lines.find do |line|
      line.includes?("SuperBlockBase#apply$") && line.includes?("_super(")
    end
    target.should_not be_nil, "lower_super did not emit a tagged target:\n#{hir}"
    target = target.not_nil!
    method_prefix = "SuperBlockBase#apply$"
    prefix_start = target.index(method_prefix).not_nil! + method_prefix.bytesize
    super_tag_end = target.index("_super(", prefix_start).not_nil! + "_super".bytesize
    suffix = target.byte_slice(prefix_start, super_tag_end - prefix_start)
    suffix.should end_with("_super")

    arena = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("")
    ).parse_program.arena
    converter = Adamas::HIR::AstToHir.new(arena)
    converter.__test_suffix_has_block_flag?(suffix).should be_false
  end

  it "lowers a defaulted named-only block_id argument as an ordinary call" do
    hir = named_block_suffix_hir(<<-CRYSTAL)
      struct MacroSymbol
      end
      struct ExprId
      end
      struct ClassSymbol
      end
      struct NamedArgument
      end

      class NamedBlockSuffixProbe
        def f(value : Int32,
              owner_type : ClassSymbol? = nil,
              *,
              named_args : Array(NamedArgument)? = nil,
              block_id : ExprId? = nil,
              preserve_unresolved_expressions : Bool = false) : Int32
          value
        end
      end

      probe = NamedBlockSuffixProbe.new
      a = probe.f(2)
      b = probe.f(3, nil)
      c = probe.f(4, nil, named_args: nil)
      d = probe.f(5, nil, named_args: nil, block_id: nil)
      e = probe.f(6, nil, named_args: nil, block_id: nil, preserve_unresolved_expressions: false)
      exit(a + b + c + d + e)
      CRYSTAL

    body = named_block_function_section(hir)
    body.should_not be_nil, "named-only source body for block_id was omitted:\n#{hir}"
    body.not_nil!.should contain("return")
    body.not_nil!.should contain("NamedBlockSuffixProbe#f$")
  end
end
