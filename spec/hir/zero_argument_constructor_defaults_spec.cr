require "../spec_helper"
require "../semantic_cli_helpers"
require "../../src/compiler/cli"

include SemanticCliSpecHelpers

private def zero_argument_constructor_hir(source : String) : String
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

describe "zero-argument constructor defaults" do
  ["ExplicitOwner.new", "ExplicitOwner.new()"].each do |constructor|
    it "keeps a declared zero-argument new body for #{constructor}" do
      hir = zero_argument_constructor_hir(<<-CRYSTAL)
        lib C
          fun putchar(value : Int32) : Int32
        end
        class ExplicitOwner
          def initialize(@value : Int32 = 42)
          end
          def self.new
            C.putchar(89)
          end
        end
        #{constructor}
        CRYSTAL

      functions = hir.scan(/^func @.*?\n\}/m).map(&.[0])
      declared_new = functions.find(&.starts_with?("func @ExplicitOwner.new("))
      declared_new.should_not be_nil, hir
      declared_new.not_nil!.should contain("putchar")
      declared_new.not_nil!.should_not contain(".ExplicitOwner#initialize")
    end
  end

  ["DefaultOwner.new", "DefaultOwner.new()"].each do |constructor|
    it "materializes a struct-valued constant for #{constructor}" do
      hir = zero_argument_constructor_hir(<<-CRYSTAL)
        struct DefaultValue
          getter value : Int32
          def initialize(@value : Int32)
          end
        end
        class DefaultOwner
          DEFAULT = DefaultValue.new(41)
          getter every
          def initialize(@every = DEFAULT)
          end
        end
        #{constructor}.every.value
        CRYSTAL

      functions = hir.scan(/^func @.*?\n\}/m).map(&.[0])
      allocator = functions.find do |body|
        body.starts_with?("func @DefaultOwner.new") &&
          body.lines.first.match(/\(\)/)
      end
      allocator.should_not be_nil, hir
      allocator.not_nil!.should contain("classvar_get DefaultOwner.@@DEFAULT")
      allocator.not_nil!.should match(/\.DefaultOwner#initialize[^\n]*\(%\d+\)/)
    end

  end

  it "refreshes an inferred ivar when initializer lowering discovers its concrete type" do
    hir = zero_argument_constructor_hir(<<-CRYSTAL)
      struct LateValue
        getter value : Int32
        def initialize(@value : Int32)
        end
      end
      class LateOwner
        DEFAULT = 41.to_late_value
        getter every
        getter other
        def initialize(@every = DEFAULT)
          @other = LateValue.new(42)
        end
      end
      class LateChild < LateOwner
      end
      struct Int32
        def to_late_value : LateValue
          LateValue.new(self)
        end
      end
      owner = LateOwner.new
      owner.every.value
      owner.other.value
      LateChild.new.every.value
      CRYSTAL

    functions = hir.scan(/^func @.*?\n\}/m).map(&.[0])
    main = functions.find(&.starts_with?("func @__adamas_main("))
    main.should_not be_nil, hir
    main.not_nil!.should_not match(/call[^\n]*LateOwner#(?:every|other)\([^\n]* : 0\b/)
    main.not_nil!.should_not match(/call[^\n]*\.value\(/)
    ["every", "other"].each do |name|
      getter = functions.find(&.starts_with?("func @LateOwner##{name}("))
      getter.should_not be_nil, hir
      getter.not_nil!.should_not match(/field_get[^\n]* : 0\b/)
      getter.not_nil!.lines.first.should_not end_with(" -> 0 {")
    end
    inherited_getter = functions.find(&.starts_with?("func @LateChild#every("))
    inherited_getter.should_not be_nil, hir
    inherited_getter.not_nil!.should_not match(/field_get[^\n]* : 0\b/)
    inherited_getter.not_nil!.lines.first.should_not end_with(" -> 0 {")
  end
end
