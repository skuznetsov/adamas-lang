require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/symbol_table"
require "../../src/compiler/semantic/symbol"
require "../../src/compiler/semantic/collectors/symbol_collector"
require "../../src/compiler/semantic/resolvers/name_resolver"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/types/type"
require "../../src/compiler/semantic/types/primitive_type"
require "../../src/compiler/semantic/types/class_type"
require "../../src/compiler/semantic/types/instance_type"
require "../../src/compiler/semantic/types/type_context"
require "../../src/compiler/semantic/type_inference_engine"

module TypeInferenceGenericsSpecAliases
  alias Frontend = CrystalV2::Compiler::Frontend
  alias Semantic = CrystalV2::Compiler::Semantic
end

include TypeInferenceGenericsSpecAliases
include CrystalV2::Compiler::Semantic

# Helper: Parse source and run full semantic pipeline
private def infer_types(source : String)
  lexer = Frontend::Lexer.new(source)
  parser = Frontend::Parser.new(lexer)
  program = parser.parse_program

  # Run semantic analysis (symbol collection + name resolution)
  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names

  # Run type inference with global symbol table for fallback lookup
  engine = Semantic::TypeInferenceEngine.new(program, name_result.identifier_symbols, analyzer.global_context.symbol_table)
  engine.infer_types

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "Week 1: Generic Type Instantiation" do

    # ========================================
    # MILESTONE 1: Basic Generic Class
    # ========================================

    describe "Generic class instantiation" do
      it "infers concrete type for generic class with explicit type args" do
        source = <<-CRYSTAL
          class Box(T)
            def initialize(value : T)
              @value = value
            end
          end

          Box(Int32).new(42)
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        # Find the Box(Int32).new(42) call expression
        # It should be the last root
        call_id = program.roots.last
        type = engine.context.get_type(call_id)

        type.should be_a(InstanceType)
        instance_type = type.as(InstanceType)

        instance_type.class_symbol.name.should eq("Box")
        instance_type.type_args.should_not be_nil
        instance_type.type_args.not_nil!.size.should eq(1)
        instance_type.type_args.not_nil![0].should be_a(PrimitiveType)
        instance_type.type_args.not_nil![0].as(PrimitiveType).name.should eq("Int32")
      end

      it "infers generic self.new receivers from class method parameter annotations" do
        source = <<-CRYSTAL
          struct Pointer(T)
          end

          class Array(T)
            def to_unsafe : Pointer(T)
              Pointer(T).new
            end

            def size : Int32
              0
            end
          end

          struct Slice(T)
            def self.new(ptr : Pointer(T), size : Int32) : self
            end
          end

          Slice.new(Array(Int32).new.to_unsafe, Array(Int32).new.size)
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        type = engine.context.get_type(program.roots.last)
        type.should be_a(ArrayType)
        type.as(ArrayType).element_type.should eq(engine.context.int32_type)
      end

      it "infers type parameter from constructor argument (type inference)" do
        source = <<-CRYSTAL
          class Box(T)
            def initialize(value : T)
              @value = value
            end
          end

          Box.new(42)
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        call_id = program.roots.last
        type = engine.context.get_type(call_id)

        type.should be_a(InstanceType)
        instance_type = type.as(InstanceType)

        # Should infer Box(Int32) from argument type
        instance_type.class_symbol.name.should eq("Box")
        instance_type.type_args.should_not be_nil
        instance_type.type_args.not_nil!.size.should eq(1)
        instance_type.type_args.not_nil![0].should be_a(PrimitiveType)
        instance_type.type_args.not_nil![0].as(PrimitiveType).name.should eq("Int32")
      end

      it "infers different type parameters for different instantiations" do
        source = <<-CRYSTAL
          class Box(T)
            def initialize(value : T)
              @value = value
            end
          end

          Box.new(42)
          Box.new("hello")
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        # First call: Box.new(42) → Box(Int32)
        first_call_id = program.roots[-2]
        first_type = engine.context.get_type(first_call_id)
        first_type.should be_a(InstanceType)
        first_type.as(InstanceType).type_args.not_nil![0].as(PrimitiveType).name.should eq("Int32")

        # Second call: Box.new("hello") → Box(String)
        second_call_id = program.roots[-1]
        second_type = engine.context.get_type(second_call_id)
        second_type.should be_a(InstanceType)
        second_type.as(InstanceType).type_args.not_nil![0].as(PrimitiveType).name.should eq("String")
      end

      it "infers namespaced generic constructors with typeof proc type arguments" do
        source = <<-CRYSTAL
          module Chunk
            struct Accumulator(T, U)
            end
          end

          def probe(block : Int32 -> String)
            Chunk::Accumulator(Int32, typeof(block.call(1))).new
          end
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        def_node = program.arena[program.roots.last].as(Frontend::DefNode)
        call_id = def_node.body.not_nil!.first
        type = engine.context.get_type(call_id)

        type.should be_a(InstanceType)
        instance_type = type.as(InstanceType)
        instance_type.class_symbol.name.should eq("Accumulator")
        instance_type.type_args.should_not be_nil
        instance_type.type_args.not_nil!.size.should eq(2)
        instance_type.type_args.not_nil![0].as(PrimitiveType).name.should eq("Int32")
        instance_type.type_args.not_nil![1].as(PrimitiveType).name.should eq("String")
      end

      it "resolves lexical namespaced generic constructors inside generic modules" do
        source = <<-CRYSTAL
          module EnumerableLike(T)
            module Chunk
              struct Accumulator(A, B)
              end
            end

            def probe : Chunk::Accumulator(T, Int32)
              Chunk::Accumulator(T, Int32).new
            end
          end
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty
      end

      it "resolves explicit type application arguments from the current generic receiver context" do
        source = <<-CRYSTAL
          class Box(T)
            class Accumulator(A, B)
              @data : Array(A)

              def initialize
                @data = [] of A
              end

              def add(value : A)
                @data << value
              end
            end

            def probe(value : T)
              acc = Accumulator(T, Int32).new
              acc.add(value)
            end
          end

          Box(String).new.probe("x")
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty
      end

      it "treats aliases to generic types as constructor receivers in expression position" do
        source = <<-CRYSTAL
          class Box(T)
          end

          alias IntBox = Box(Int32)

          IntBox.new
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)

        type.should be_a(InstanceType)
        instance_type = type.as(InstanceType)
        instance_type.class_symbol.name.should eq("Box")
        instance_type.type_args.should_not be_nil
        instance_type.type_args.not_nil!.size.should eq(1)
        instance_type.type_args.not_nil![0].should be_a(PrimitiveType)
        instance_type.type_args.not_nil![0].as(PrimitiveType).name.should eq("Int32")
      end

      it "treats type parameters as primitive class receivers in expression position" do
        source = <<-CRYSTAL
          struct Wrap(T)
            def build(value : T)
              T.new!(value)
            end

            def zero
              T.zero
            end
          end

          Wrap(UInt64).new.build(1_u64)
          Wrap(UInt64).new.zero
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        build_call_id = program.roots[-2]
        build_type = engine.context.get_type(build_call_id)
        build_type.should be_a(PrimitiveType)
        build_type.as(PrimitiveType).name.should eq("UInt64")

        zero_call_id = program.roots[-1]
        zero_type = engine.context.get_type(zero_call_id)
        zero_type.should be_a(PrimitiveType)
        zero_type.as(PrimitiveType).name.should eq("UInt64")
      end
    end

    # ========================================
    # MILESTONE 2: Generic Methods
    # ========================================

    describe "Generic class methods" do
      it "returns correct type from generic method" do
        source = <<-CRYSTAL
          class Box(T)
            def initialize(value : T)
              @value = value
            end

            def get : T
              @value
            end
          end

          box = Box.new(42)
          box.get
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        # Find box.get call (should be last root)
        get_call_id = program.roots.last
        type = engine.context.get_type(get_call_id)

        # Should return Int32 (substituted from T)
        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end

      it "handles multiple type parameters" do
        source = <<-CRYSTAL
          class Pair(K, V)
            def initialize(key : K, value : V)
              @key = key
              @value = value
            end

            def key : K
              @key
            end

            def value : V
              @value
            end
          end

          pair = Pair.new("name", 42)
          pair.key
          pair.value
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        # pair.key should be String
        key_call_id = program.roots[-2]
        key_type = engine.context.get_type(key_call_id)
        key_type.should be_a(PrimitiveType)
        key_type.as(PrimitiveType).name.should eq("String")

        # pair.value should be Int32
        value_call_id = program.roots[-1]
        value_type = engine.context.get_type(value_call_id)
        value_type.should be_a(PrimitiveType)
        value_type.as(PrimitiveType).name.should eq("Int32")
      end
    end

    # ========================================
    # MILESTONE 3: Generic Instance Variables
    # ========================================

    describe "Generic instance variables" do
      it "infers correct type for generic instance variable access" do
        source = <<-CRYSTAL
          class Box(T)
            def initialize(value : T)
              @value = value
            end

            def direct_value
              @value
            end
          end

          box = Box.new(42)
          box.direct_value
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        # box.direct_value should return Int32
        call_id = program.roots.last
        type = engine.context.get_type(call_id)

        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end
    end

    # ========================================
    # MILESTONE 4: Nested Generics
    # ========================================

    describe "Nested generic types" do
      it "handles generic type as type argument" do
        source = <<-CRYSTAL
          class Box(T)
            def initialize(value : T)
              @value = value
            end

            def get : T
              @value
            end
          end

          class Container(T)
            def initialize(item : T)
              @item = item
            end

            def item : T
              @item
            end
          end

          inner = Box.new(42)
          outer = Container.new(inner)
          outer.item
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        # outer.item should return Box(Int32)
        item_call_id = program.roots.last
        type = engine.context.get_type(item_call_id)

        type.should be_a(InstanceType)
        instance_type = type.as(InstanceType)
        instance_type.class_symbol.name.should eq("Box")
        instance_type.type_args.not_nil![0].as(PrimitiveType).name.should eq("Int32")
      end
    end

    # ========================================
    # EXECUTION_PLAN.md Week 1 Success Criteria
    # ========================================

    describe "Week 1 Success Criteria from EXECUTION_PLAN.md" do
      it "passes Box(T) example from execution plan" do
        source = <<-CRYSTAL
          class Box(T)
            def initialize(value : T)
              @value = value
            end

            def get : T
              @value
            end
          end

          box = Box.new(42)
          box.get
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        # box should be Box(Int32)
        box_assignment_id = program.roots[-2]
        box_type = engine.context.get_type(box_assignment_id)
        box_type.should be_a(InstanceType)
        box_type.as(InstanceType).type_args.not_nil![0].as(PrimitiveType).name.should eq("Int32")

        # box.get should return Int32
        get_call_id = program.roots.last
        get_type = engine.context.get_type(get_call_id)
        get_type.should be_a(PrimitiveType)
        get_type.as(PrimitiveType).name.should eq("Int32")
      end
    end
  end

  describe "Week 1 Day 2: Generic Methods" do

    # ========================================
    # MILESTONE 1: Basic Generic Method
    # ========================================

    describe "Generic method with single type parameter" do
      it "does not emit arithmetic diagnostics for abstract generic bodies before instantiation" do
        source = <<-CRYSTAL
          def accumulateish(x : T, y : T) forall T
            x + y
          end
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty
      end

      it "infers type parameter from argument" do
        source = <<-CRYSTAL
          def identity(x : T) : T
            x
          end

          identity(42)
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        # identity(42) should return Int32
        call_id = program.roots.last
        type = engine.context.get_type(call_id)

        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end

      it "works with different argument types" do
        source = <<-CRYSTAL
          def identity(x : T) : T
            x
          end

          identity(42)
          identity("hello")
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        # First call: identity(42) → Int32
        first_call_id = program.roots[-2]
        first_type = engine.context.get_type(first_call_id)
        first_type.should be_a(PrimitiveType)
        first_type.as(PrimitiveType).name.should eq("Int32")

        # Second call: identity("hello") → String
        second_call_id = program.roots[-1]
        second_type = engine.context.get_type(second_call_id)
        second_type.should be_a(PrimitiveType)
        second_type.as(PrimitiveType).name.should eq("String")
      end
    end

    # ========================================
    # MILESTONE 2: Multiple Type Parameters
    # ========================================

    describe "Generic method with multiple type parameters" do
      it "infers multiple type parameters from arguments" do
        source = <<-CRYSTAL
          def pair(first : T, second : U) : T
            first
          end

          pair(42, "hello")
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        # pair(42, "hello") should return Int32 (type of first)
        call_id = program.roots.last
        type = engine.context.get_type(call_id)

        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end

      it "does not emit collection builder diagnostics for abstract generic bodies before instantiation" do
        source = <<-CRYSTAL
          class Array(T)
          end

          class Hash(K, V)
          end

          def groupish(value : T, & : T -> U) forall T, U
            h = Hash(U, Array(T)).new
            key = yield value
            h.put_if_absent(key) { Array(T).new } << value
          end
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty
      end

      it "resolves Reflect(T).type inside non-generic methods of generic owners" do
        source = <<-CRYSTAL
          class Wrapper(T)
            struct Reflect(X)
              def self.type
                X
              end
            end

            def productish
              Reflect(T).type
            end
          end

          Wrapper(Int32).new.productish
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end

      it "resolves Reflect(T).type inside generic module self methods" do
        source = <<-CRYSTAL
          module Wrapper(T)
            struct Reflect(X)
              def self.type
                X
              end
            end

            def self.productish
              Reflect(T).type
            end
          end

          Wrapper(Int32).productish
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end

      it "resolves typeof(yield Enumerable.element_type(self)) inside generic modules" do
        source = <<-CRYSTAL
          module Enumerable(T)
            struct Reflect(X)
              def self.type
                X
              end
            end

            abstract def each(& : T ->)

            def productish(& : T -> _)
              Reflect(typeof(yield Enumerable.element_type(self))).type
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

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end

      it "resolves Reflect(T).type inside generic modules included into classes" do
        source = <<-CRYSTAL
          module Enumerable(T)
            struct Reflect(X)
              def self.type
                X
              end
            end

            def productish
              Reflect(T).type
            end
          end

          class Box
            include Enumerable(Int32)
          end

          Box.new.productish
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end

      it "resolves T.class annotations inside generic modules" do
        source = <<-CRYSTAL
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

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end

      it "preserves array element type through flat_map_type in generic modules" do
        source = <<-CRYSTAL
          class Array(T)
            def first : T
              uninitialized T
            end
          end

          module Enumerable(T)
            abstract def each(& : T ->)

            def self.element_type(value) : T
              uninitialized T
            end

            private def flat_map_type(elem)
              case elem
              when Array
                elem.first
              else
                elem
              end
            end

            def flat_mapish(& : T -> _)
              [] of typeof(flat_map_type(yield Enumerable.element_type(self)))
            end
          end

          class Box
            include Enumerable(Int32)

            def each(& : Int32 ->)
              yield 1
            end
          end

          Box.new.flat_mapish { |x| [x + 1] }
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(ArrayType)
      end

      it "handles flat_map_type branches with Array and Iterator in generic modules" do
        source = <<-CRYSTAL
          module Iterator(T)
            abstract def first : T
          end

          class Array(T)
            include Iterator(T)

            def first : T
              uninitialized T
            end
          end

          module Enumerable(T)
            abstract def each(& : T ->)

            def self.element_type(value) : T
              uninitialized T
            end

            private def flat_map_type(elem)
              case elem
              when Array, Iterator
                elem.first
              else
                elem
              end
            end

            def flat_mapish(& : T -> _)
              [] of typeof(flat_map_type(yield Enumerable.element_type(self)))
            end
          end

          class Box
            include Enumerable(Int32)

            def each(& : Int32 ->)
              yield 1
            end
          end

          Box.new.flat_mapish { |x| [x + 1] }
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(ArrayType)
      end

      it "resolves indexed Enumerable.element_type(self) inside generic modules" do
        source = <<-CRYSTAL
          class Hash(K, V)
            def initialize
            end
          end

          module Enumerable(T)
            abstract def each(& : T ->)

            def self.element_type(value) : T
              uninitialized T
            end

            def to_hish
              Hash(typeof(Enumerable.element_type(self)[0]), typeof(Enumerable.element_type(self)[1])).new
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

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(HashType)
        hash_type = type.as(HashType)
        hash_type.key_type.should be_a(PrimitiveType)
        hash_type.key_type.as(PrimitiveType).name.should eq("Int32")
        hash_type.value_type.should be_a(PrimitiveType)
        hash_type.value_type.as(PrimitiveType).name.should eq("String")
      end

      it "propagates reduce accumulator types through included generic modules" do
        source = <<-CRYSTAL
          module Enumerable(T)
            abstract def each(& : T ->)

            def reduce(initial : U, & : U, T -> U) : U forall U
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

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end

      it "propagates untyped reduce block params through included generic modules" do
        source = <<-CRYSTAL
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

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end

      it "propagates untyped each_with_object block params through included generic modules" do
        source = <<-CRYSTAL
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

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(HashType)
        hash_type = type.as(HashType)
        hash_type.key_type.should be_a(PrimitiveType)
        hash_type.key_type.as(PrimitiveType).name.should eq("Int32")
        hash_type.value_type.should be_a(PrimitiveType)
        hash_type.value_type.as(PrimitiveType).name.should eq("String")
      end

      it "propagates transitive included-module type args through untyped reduce blocks" do
        source = <<-CRYSTAL
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

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("String")
      end

      it "propagates transitive included-module type args through untyped each_with_object blocks" do
        source = <<-CRYSTAL
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

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(HashType)
        hash_type = type.as(HashType)
        hash_type.key_type.should be_a(PrimitiveType)
        hash_type.key_type.as(PrimitiveType).name.should eq("String")
        hash_type.value_type.should be_a(PrimitiveType)
        hash_type.value_type.as(PrimitiveType).name.should eq("Int32")
      end

      it "expands record macros with generic names inside modules" do
        source = <<-CRYSTAL
          macro record(__name name, *properties, **kwargs)
            struct {{name.id}}
            end
          end

          module FastFloat
            record FromCharsResultT(UC), ptr : UC*, ec : Int32
          end

          FastFloat::FromCharsResultT(UInt8).new
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(InstanceType)
        instance_type = type.as(InstanceType)
        instance_type.class_symbol.name.should eq("FromCharsResultT")
        instance_type.type_args.should_not be_nil
        instance_type.type_args.not_nil!.first.should be_a(PrimitiveType)
        instance_type.type_args.not_nil!.first.as(PrimitiveType).name.should eq("UInt8")
      end

      it "expands record macros inside class-owned module reopens" do
        source = <<-CRYSTAL
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

        program, analyzer, engine = infer_types(source)

        analyzer.semantic_diagnostics.should be_empty
        analyzer.name_resolver_diagnostics.should be_empty
        engine.diagnostics.should be_empty

        call_id = program.roots.last
        type = engine.context.get_type(call_id)
        type.should be_a(InstanceType)
        type.as(InstanceType).class_symbol.name.should eq("Point")
      end
    end

    # ========================================
    # MILESTONE 3: Generic Method with Generic Types
    # ========================================

    describe "Generic method with generic class arguments" do
      it "infers type parameters from generic class instances" do
        source = <<-CRYSTAL
          class Box(T)
            def initialize(value : T)
              @value = value
            end

            def get : T
              @value
            end
          end

          def unwrap(box : Box(T)) : T
            box.get
          end

          box = Box.new(42)
          unwrap(box)
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        # unwrap(box) should return Int32
        call_id = program.roots.last
        type = engine.context.get_type(call_id)

        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end
    end

    # ========================================
    # MILESTONE 4: Chained Generic Method Calls
    # ========================================

    describe "Chained generic method calls" do
      it "propagates type parameters through chain" do
        source = <<-CRYSTAL
          def identity(x : T) : T
            x
          end

          def wrap(x : T) : T
            identity(x)
          end

          wrap(42)
        CRYSTAL

        program, analyzer, engine = infer_types(source)

        # wrap(42) should return Int32
        call_id = program.roots.last
        type = engine.context.get_type(call_id)

        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("Int32")
      end
    end
  end
end

  describe "Default Parameter Values" do
    it "accepts fewer arguments when defaults are provided" do
      source = <<-CRYSTAL
        def greet(name : String, greeting : String = "Hello") : String
          greeting + " " + name
        end

        greet("World")
      CRYSTAL

      program, analyzer, engine = infer_types(source)

      call_id = program.roots.last
      type = engine.context.get_type(call_id)

      type.should be_a(PrimitiveType)
      type.as(PrimitiveType).name.should eq("String")

      engine.diagnostics.select(&.level.error?).should be_empty
    end

    it "accepts full arguments with defaults" do
      source = <<-CRYSTAL
        def greet(name : String, greeting : String = "Hello") : String
          greeting + " " + name
        end

        greet("World", "Hi")
      CRYSTAL

      program, analyzer, engine = infer_types(source)

      call_id = program.roots.last
      type = engine.context.get_type(call_id)

      type.should be_a(PrimitiveType)
      type.as(PrimitiveType).name.should eq("String")

      engine.diagnostics.select(&.level.error?).should be_empty
    end

    it "handles multiple default parameters" do
      source = <<-CRYSTAL
        def config(host : String = "localhost", port : Int32 = 8080, ssl : Bool = false) : String
          host
        end

        config()
        config("example.com")
        config("example.com", 443)
        config("example.com", 443, true)
      CRYSTAL

      program, analyzer, engine = infer_types(source)

      # All calls should return String
      [-4, -3, -2, -1].each do |offset|
        call_id = program.roots[offset]
        type = engine.context.get_type(call_id)
        type.should be_a(PrimitiveType)
        type.as(PrimitiveType).name.should eq("String")
      end

      engine.diagnostics.select(&.level.error?).should be_empty
    end
  end
