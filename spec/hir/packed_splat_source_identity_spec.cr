require "../spec_helper"
require "../semantic_cli_helpers"
require "../../src/compiler/cli"

include SemanticCliSpecHelpers

private def packed_splat_source_hir(source : String) : {Int32, String, String}
  with_temp_shadow_project({"main.cr" => source}) do |dir|
    target = File.join(dir, "main")
    errors = IO::Memory.new
    status = Adamas::Compiler::CLI.new([
      File.join(dir, "main.cr"), "--no-prelude", "--emit", "hir",
      "--no-link", "--no-llvm-cache", "-o", target,
    ]).run(out_io: IO::Memory.new, err_io: errors)
    hir = File.exists?("#{target}.hir") ? File.read("#{target}.hir") : ""
    {status, hir, errors.to_s}
  end
end

describe "source identity for packed positional splat calls" do
  it "materializes typed rest bodies under the selected per-arity Tuple ABI alongside a getter" do
    status, hir, errors = packed_splat_source_hir(<<-CRYSTAL)
      require "object/properties"
      require "comparable"
      require "tuple"

      class PackedTypedGetter
        def initialize(@value : Int32)
        end

        getter value : Int32

        def value(*args : Int32) : Int32
          if args.size == 1
            66
          else
            67
          end
        end
      end

      receiver = PackedTypedGetter.new(65)
      receiver.value
      receiver.value(1)
      receiver.value(1, 2)
    CRYSTAL

    status.should eq(0), errors
    hir.should contain("call %")
    hir.should contain("PackedTypedGetter#value()")
    hir.should contain("PackedTypedGetter#value$Tuple(Int32)_splat")
    hir.should contain("PackedTypedGetter#value$Tuple(Int32, Int32)_splat")
    hir.should contain("func @PackedTypedGetter#value$Tuple(Int32)_splat")
    hir.should contain("func @PackedTypedGetter#value$Tuple(Int32, Int32)_splat")
  end

  it "keeps untyped and Int64 rest calls specialized by one- and two-element Tuple ABI" do
    status, hir, errors = packed_splat_source_hir(<<-CRYSTAL)
      require "comparable"
      require "tuple"

      class PackedUntypedRest
        def value(*args) : Int32
          if args.size == 1
            68
          else
            69
          end
        end
      end

      class PackedInt64Rest
        def value(*args : Int64) : Int32
          if args.size == 1
            70
          else
            71
          end
        end
      end

      untyped = PackedUntypedRest.new
      int64 = PackedInt64Rest.new
      first : Int64 = 1_i64
      second : Int64 = 2_i64
      untyped.value(first)
      untyped.value(first, second)
      int64.value(first)
      int64.value(first, second)
    CRYSTAL

    status.should eq(0), errors
    [
      "PackedUntypedRest#value$Tuple(Int64)",
      "PackedUntypedRest#value$Tuple(Int64, Int64)",
      "PackedInt64Rest#value$Tuple(Int64)_splat",
      "PackedInt64Rest#value$Tuple(Int64, Int64)_splat",
    ].each do |target|
      hir.should contain(target)
      hir.should contain("func @#{target}")
    end
  end

  it "does not let a rest overload displace a fixed overload in either source order" do
    status, hir, errors = packed_splat_source_hir(<<-CRYSTAL)
      class PackedFixedFirst
        def pick(value : Int32) : Int32
          69
        end

        def pick(*values : Int32) : Int32
          70
        end
      end

      class PackedRestFirst
        def pick(*values : Int32) : Int32
          70
        end

        def pick(value : Int32) : Int32
          69
        end
      end

      PackedFixedFirst.new.pick(1)
      PackedFixedFirst.new.pick(1, 2)
      PackedRestFirst.new.pick(1)
      PackedRestFirst.new.pick(1, 2)
    CRYSTAL

    status.should eq(0), errors
    calls = hir.lines.select { |line| line.includes?("call ") && line.includes?("#pick") }
    calls.size.should eq(4), hir
    calls[0].should contain("PackedFixedFirst#pick$Int32")
    calls[0].should_not contain("_splat")
    calls[1].should contain("PackedFixedFirst#pick$Tuple(Int32, Int32)_splat")
    calls[2].should contain("PackedRestFirst#pick$Int32")
    calls[2].should_not contain("_splat")
    calls[3].should contain("PackedRestFirst#pick$Tuple(Int32, Int32)_splat")
  end

  it "rejects an element outside the typed rest restriction" do
    status, _hir, errors = packed_splat_source_hir(<<-CRYSTAL)
      class PackedWrongElement
        def accept(*values : Int32) : Int32
          1
        end
      end

      PackedWrongElement.new.accept(true)
    CRYSTAL

    status.should_not eq(0)
    errors.should contain("error: no overload matches PackedWrongElement#accept for argument types (Bool)")
  end
end
