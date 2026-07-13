require "./semantic_cli_helpers"

include SemanticCliSpecHelpers

describe Adamas::Compiler::CLI do
  it "keeps semantic compile prepass green for splat call traversal" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        def consume(*values)
        end

        values = [1]
        consume(*values)
      CRYSTAL
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for T.class annotation dispatch" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        class Int32
          def self.multiplicative_identity
            1
          end
        end

        module Reflect(T)
          def self.type : T.class
            T
          end
        end

        module Enumerable(T)
          abstract def each(& : T ->)

          def self.element_type(value) : T
            uninitialized T
          end

          def productish(& : T -> _)
            Reflect(typeof(yield Enumerable.element_type(self))).type.multiplicative_identity
          end
        end

        class Box
          include Enumerable(Int32)

          def each(& : Int32 ->)
            yield 1
          end
        end

        Box.new.productish { |x| x + 1 }
      CRYSTAL
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for untyped reduce block propagation" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        module Enumerable(T)
          abstract def each(& : T ->)

          def reduce(initial, &)
            memo = initial
            each do |e|
              memo = yield memo, e
            end
            memo
          end

          def sumish(initial : Number, & : T ->)
            reduce(initial) { |memo, e| memo + (yield e) }
          end
        end

        class Number
        end

        class Int32 < Number
        end

        class Box
          include Enumerable(Int32)

          def each(& : Int32 ->)
            yield 1
          end
        end

        Box.new.sumish(0) { |x| x + 1 }
      CRYSTAL
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for untyped each_with_object block propagation" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        class Hash(K, V)
          def initialize
          end

          def []=(key : K, value : V) : V
            value
          end
        end

        module Enumerable(T)
          abstract def each(& : T ->)

          def self.element_type(value) : T
            uninitialized T
          end

          def each_with_object(obj, &)
            each do |elem|
              yield elem, obj
            end
            obj
          end

          def to_hish
            each_with_object(Hash(typeof(Enumerable.element_type(self)[0]), typeof(Enumerable.element_type(self)[1])).new) do |item, hash|
              hash[item[0]] = item[1]
            end
          end
        end

        class Pairs
          include Enumerable(Tuple(Int32, String))

          def each(& : Tuple(Int32, String) ->)
            yield {1, "x"}
          end
        end

        Pairs.new.to_hish
      CRYSTAL
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for transitive included-module reduce propagation" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        class String
          def +(other : String) : String
            self
          end
        end

        module Enumerable(T)
          abstract def each(& : T ->)

          def reduce(initial, &)
            memo = initial
            each do |elem|
              memo = yield memo, elem
            end
            memo
          end

          def sum(initial)
            sum initial, &.itself
          end

          def sum(initial, & : T ->)
            reduce(initial) { |memo, e| memo + (yield e) }
          end
        end

        module Indexable(T)
          include Enumerable(T)
        end

        class Names
          include Indexable(String)

          def each(& : String ->)
            yield "x"
          end
        end

        Names.new.sum("")
      CRYSTAL
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for transitive included-module each_with_object propagation" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        class Hash(K, V)
          def initialize
          end

          def fetch(key : K)
            yield
          end

          def [](key : K) : V
            uninitialized V
          end

          def []=(key : K, value : V) : V
            value
          end
        end

        class Int32
          def +(other : Int32) : Int32
            self
          end

          def self.zero : Int32
            0
          end
        end

        class String
          def downcase : String
            self
          end
        end

        module Enumerable(T)
          abstract def each(& : T ->)

          def each_with_object(obj, &)
            each do |elem|
              yield elem, obj
            end
            obj
          end

          def tally_by(hash, &)
            each_with_object(hash) do |item, hash|
              value = yield item
              count = hash.fetch(value) { typeof(hash[value]).zero }
              hash[value] = count + 1
            end
          end
        end

        module Indexable(T)
          include Enumerable(T)
        end

        class Names
          include Indexable(String)

          def each(& : String ->)
            yield "x"
          end
        end

        Names.new.tally_by(Hash(String, Int32).new, &.downcase)
      CRYSTAL
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for record macros inside class-owned module reopens" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        macro record(__name name, *properties, **kwargs)
          struct {{name.id}}
          end
        end

        struct Float
        end

        module Float::FastFloat
          record Point, x : Int32
        end

        Float::FastFloat::Point.new
      CRYSTAL
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("Semantic compile prepass:")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for stdlib record macros with user-defined generic type applications" do
    with_temp_shadow_project({
      "main.cr" => <<-CRYSTAL,
        require #{File.expand_path("../src/stdlib/object/properties", __DIR__).inspect}
        require #{File.expand_path("../src/stdlib/macros", __DIR__).inspect}

        struct Object
        end

        struct Value
        end

        struct Number < Value
        end

        struct Int32 < Number
        end

        struct UInt8 < Number
        end

        struct Float
        end

        module Float::FastFloat
          @[Flags]
          enum CharsFormat
            General = 0
          end

          record ParseOptionsT(UC), format : CharsFormat = :general, decimal_point : UC = 0x2E
          alias ParseOptions = ParseOptionsT(UInt8)
        end

        Float::FastFloat::ParseOptions.new
      CRYSTAL
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for camel-cased enum flag predicate methods" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        @[Flags]
        enum CharsFormat
          JsonFmt = 1 << 0
          Fixed = 1 << 1
        end

        struct ParseOptionsT(UC)
          def initialize(@format : CharsFormat = :json_fmt)
          end

          def format : CharsFormat
            @format
          end
        end

        def probe(options : ParseOptionsT(UInt8))
          options.format.json_fmt?
        end

        probe(ParseOptionsT(UInt8).new)
      CRYSTAL
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for brace tuple type identifiers in generic arguments" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        class Array(T)
          def self.new(size : Int32)
            self
          end
        end

        Array({UInt64, UInt64, UInt64}).new(1)
      CRYSTAL
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end
end
