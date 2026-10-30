require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_double_splat_literal_binding(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source},
  )
  converter.arena = program.arena
  converter.no_prelude = true

  main_exprs = [] of UInt64
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main_exprs << root.index.to_u64
    end
  end
  converter.lower_main(main_exprs)
  converter.flush_pending_functions
  converter
end

describe "direct double-splat literal call binding" do
  it "rejects unknown keys instead of emitting an unbound block call" do
    expect_raises(Adamas::HIR::LoweringError, "no overload matches binding_target") do
      lower_double_splat_literal_binding(<<-CRYSTAL)
        def binding_target(*, first : Int32, &block : -> Int32) : Int32; yield; end
        binding_target(**{first: 65, unknown: 66}) { 67 }
        CRYSTAL
    end
  end

  it "rejects a missing required key even when its defaulted sibling is supplied" do
    expect_raises(Adamas::HIR::LoweringError, "no overload matches binding_target") do
      lower_double_splat_literal_binding(<<-CRYSTAL)
        def binding_target(*, first : Int32, second : Int32 = 68, &block : -> Int32) : Int32; yield; end
        binding_target(**{second: 66}) { 67 }
        CRYSTAL
    end
  end

  it "rejects the wrong source type before constructing selected ABI slots" do
    expect_raises(Adamas::HIR::LoweringError, "no overload matches binding_target") do
      lower_double_splat_literal_binding(<<-CRYSTAL)
        def binding_target(*, first : Int32, &block : -> Int32) : Int32; yield; end
        binding_target(**{first: true}) { 67 }
        CRYSTAL
    end
  end

  it "keeps a double-splat field's Int32 type instead of autocasting its literal initializer" do
    expect_raises(Adamas::HIR::LoweringError, "no overload matches binding_target") do
      lower_double_splat_literal_binding(<<-CRYSTAL)
        def binding_target(*, first : UInt8, &block : -> Int32) : Int32; yield; end
        binding_target(**{first: 65}) { 67 }
        CRYSTAL
    end
  end

  it "rejects duplicate labels between double splats and explicit named arguments" do
    expect_raises(Adamas::HIR::LoweringError, "duplicate key: first") do
      lower_double_splat_literal_binding(<<-CRYSTAL)
        def binding_target(*, first : Int32, &block : -> Int32) : Int32; yield; end
        binding_target(**{first: 65}, first: 66) { 67 }
        CRYSTAL
    end
  end

  it "keeps explicit named literal conversion after a multi-slot positional splat" do
    converter = lower_double_splat_literal_binding(<<-CRYSTAL)
      def binding_target(first : Int32, second : Int32, *, third : UInt8, extra : Int32 = 68, &block : -> Int32) : Int32
        yield
      end
      binding_target(*{65, 66}, third: 67) { 69 }
      binding_target(*{65, 66}, **{extra: 68}, third: 67) { 69 }
      CRYSTAL
    main = converter.module.functions.find(&.name.ends_with?("main")).not_nil!
    casts = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Cast))
    casts.count { |cast| cast.type == Adamas::HIR::TypeRef::UINT8 }.should eq(2)
  end

  it "does not grant literal conversion privileges to an extracted positional slot" do
    expect_raises(Adamas::HIR::LoweringError, "no overload matches binding_target") do
      lower_double_splat_literal_binding(<<-CRYSTAL)
        def binding_target(first : UInt8, second : Int32, *, third : UInt8, &block : -> Int32) : Int32
          yield
        end
        binding_target(*{65, 66}, third: 67) { 69 }
        CRYSTAL
    end
  end

  it "takes a local double-splat layout after earlier actuals have executed" do
    converter = lower_double_splat_literal_binding(<<-CRYSTAL)
      def binding_target(marker : Int32, *, second : Int32) : Int32
        marker + second
      end
      options = {first: 65}
      binding_target((options = {second: 66}; 65), **options)
      CRYSTAL
    main = converter.module.functions.find(&.name.ends_with?("main")).not_nil!
    calls = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .select(&.method_name.starts_with?("binding_target"))
    calls.size.should eq(1)
    calls.first.args.size.should eq(2)
  end

  it "normalizes literal and local NamedTuple keys into named-only slots and keeps the block separate" do
    converter = lower_double_splat_literal_binding(<<-CRYSTAL)
      def binding_target(*, first : Int32, second : Int32 = 68, &block : -> Int32) : Int32
        yield first + second
      end

      binding_target(**{second: 66, first: 65}) { 67 }
      options = {second: 69, first: 68}
      binding_target(**options) { 70 }
      binding_target(**{first: 65}) { 67 }
      CRYSTAL

    main = converter.module.functions.find(&.name.ends_with?("main")).not_nil!
    values = main.blocks.flat_map(&.instructions)
    additions = values.compact_map(&.as?(Adamas::HIR::BinaryOperation))
      .select { |operation| operation.op == Adamas::HIR::BinaryOp::Add }
    # Each selected body consumes two ordinary Int32 slots. Neither the
    # NamedTuple aggregate nor its separate callback can become an operand.
    additions.size.should eq(3)
    additions.each do |addition|
      [addition.left, addition.right].each do |argument_id|
        values.find { |value| value.id == argument_id }.not_nil!.type.should eq(Adamas::HIR::TypeRef::INT32)
      end
    end
  end
end
