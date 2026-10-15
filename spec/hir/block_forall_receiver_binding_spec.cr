require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_block_forall_receiver_binding(source : String) : Adamas::HIR::Module
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(program.arena, sources_by_arena: {program.arena.object_id.to_u64 => source})
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |root|
    if node = program.arena[root].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
    else
      main << root.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter.module
end

describe "block forall binding after generic receiver registration" do
  it "keeps the inferred block result over a synthetic receiver U alias" do
    mod = lower_block_forall_receiver_binding(<<-CRYSTAL)
      class BlockResultOwner(T, N)
        def check(&block : T, T -> U) : Int32 forall U
          {% unless U == Int32 && T == Int32 && N == 2 %}
            {% raise "block result or receiver binding was overwritten" %}
          {% end %}
          41
        end
      end
      BlockResultOwner(Int32, 2).new.check { |left, right| 1 }
    CRYSTAL
    mod.functions.any? { |function| function.name.includes?("#check") && function.return_type == Adamas::HIR::TypeRef::INT32 }.should be_true
  end

  it "lets a method forall shadow a declared owner parameter of the same name" do
    lower_block_forall_receiver_binding(<<-CRYSTAL)
      class ShadowedBlockOwner(T, U)
        def check(&block : T -> U) : Int32 forall U
          {% unless U == Int64 && T == Int32 %}
            {% raise "method forall lost to owner U" %}
          {% end %}
          42
        end
      end
      ShadowedBlockOwner(Int32, UInt8).new.check { |value| 1_i64 }
    CRYSTAL
  end

  it "retains an owner U when the block result is a concrete annotation" do
    lower_block_forall_receiver_binding(<<-CRYSTAL)
      class ConcreteBlockOwner(T, U)
        def check(&block : T -> Int32) : Int32
          {% unless U == UInt8 && T == Int32 %}
            {% raise "concrete block annotation rebound the owner U" %}
          {% end %}
          43
        end
      end
      ConcreteBlockOwner(Int32, UInt8).new.check { |value| 1 }
    CRYSTAL
  end
end


describe "literal generic arguments in method macro context" do
  it "keeps a numeric generic argument as a number node" do
    lower_block_forall_receiver_binding(<<-CRYSTAL)
      class NumericLiteralOwner(N)
        def check : Int32
          {% unless N.class_name == "NumberLiteral" && N == 2 && N != 3 && N + 1 == 3 %}
            {% raise "numeric generic argument lost its literal kind or value" %}
          {% end %}
          44
        end
      end
      NumericLiteralOwner(2).new.check
    CRYSTAL
  end

  it "preserves a hexadecimal generic argument" do
    lower_block_forall_receiver_binding(<<-CRYSTAL)
      class HexLiteralOwner(N)
        def check : Int32
          {% unless N.class_name == "NumberLiteral" && N == 2 %}
            {% raise "generic hexadecimal value was lost" %}
          {% end %}
          45
        end
      end
      HexLiteralOwner(0x2).new.check
    CRYSTAL
  end

  it "preserves the declared integer kind of a generic argument" do
    lower_block_forall_receiver_binding(<<-CRYSTAL)
      class TypedLiteralOwner(N)
        def check : Int32
          {% unless N.class_name == "NumberLiteral" && N == 2_i64 && N != 2_i32 %}
            {% raise "generic integer kind was lost" %}
          {% end %}
          45
        end
      end
      TypedLiteralOwner(2_i64).new.check
    CRYSTAL
  end

  it "still rejects a different numeric generic value" do
    expect_raises(Adamas::HIR::LoweringError, "wrong literal rejected") do
      lower_block_forall_receiver_binding(<<-CRYSTAL)
        class WrongLiteralOwner(N)
          def check : Int32
            {% unless N == 2 %}
              {% raise "wrong literal rejected" %}
            {% end %}
            44
          end
        end
        WrongLiteralOwner(3).new.check
      CRYSTAL
    end
  end
end
