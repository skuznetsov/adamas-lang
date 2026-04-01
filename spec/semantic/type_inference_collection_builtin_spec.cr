require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_collection_builtin_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "collection and integer builtin surface" do
    it "supports integer zero? and unsafe_chr" do
      source = <<-'CRYSTAL'
        flag = 0.zero?
        char = 97.unsafe_chr
        char
      CRYSTAL

      program, analyzer, engine = infer_collection_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots[0]).to_s.should eq("Bool")
      engine.context.get_type(program.roots.last).to_s.should eq("Char")
    end

    it "supports array sort! and bsearch with blocks" do
      source = <<-'CRYSTAL'
        cccs = [{3, 2_u8}, {1, 1_u8}, {2, 3_u8}]
        cccs.sort! { |x, y| x[1] <=> y[1] }

        result = if value = cccs.bsearch { |entry| 2_u8 <= entry[1] }
                   value[0]
                 else
                   0
                 end

        result
      CRYSTAL

      program, analyzer, engine = infer_collection_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "supports array and hash clone plus array delete and map_with_index" do
      source = <<-'CRYSTAL'
        flags = ["alpha"]
        handlers = {"alpha" => 3}

        old_flags = flags.clone
        old_handlers = handlers.clone
        removed = old_flags.delete("alpha")
        mapped = ["beta"].map_with_index { |value, i| value }

        (old_handlers["alpha"]? || 0) + (removed || mapped[0]).bytesize
      CRYSTAL

      program, analyzer, engine = infer_collection_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "supports array join with io and char separator" do
      source = <<-'CRYSTAL'
        class IO
        end

        flags = ["alpha", "beta"]
        io = uninitialized IO
        flags.join io, '\n'
      CRYSTAL

      program, analyzer, engine = infer_collection_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Nil")
    end

    it "supports hash put with a block" do
      source = <<-'CRYSTAL'
        class Hash(K, V)
        end

        hash = Hash(Tuple(UInt64, Symbol), Nil).new
        key = {1_u64, :x}

        hash.put(key, nil) do
          true
        ensure
          hash.delete(key)
        end
      CRYSTAL

      program, analyzer, engine = infer_collection_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
    end

    it "supports deque queue operations and each blocks" do
      source = <<-'CRYSTAL'
        class Text
          getter width

          def initialize(@width : Int32)
          end
        end

        class Breakable
          getter width

          def initialize(@width : Int32)
          end
        end

        class Deque(T)
        end

        class Box
          def initialize
            @buffer = Deque(Text | Breakable).new
          end

          def seed
            @buffer << Text.new(2)
            @buffer.push Breakable.new(3)
          end

          def drain
            total = 0
            @buffer.each do |data|
              total += data.width
            end
            first = @buffer.shift
            @buffer.clear
            total + first.width
          end
        end

        box = Box.new
        box.seed
        box.drain
      CRYSTAL

      program, analyzer, engine = infer_collection_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "scopes untyped ivar inference by owner for deque-like buffers" do
      source = <<-'CRYSTAL'
        class Text
          getter width

          def initialize(@width : Int32)
          end
        end

        class Breakable
          getter width

          def initialize(@width : Int32)
          end
        end

        class Pointer(T)
          def self.null
            uninitialized self
          end

          def shift
            uninitialized T
          end

          def clear
            self
          end
        end

        class Deque(T)
          @buffer : Pointer(T)

          def initialize
            @buffer = Pointer(T).null
          end

          def storage
            @buffer
          end
        end

        class Box
          @buffer = Deque(Text | Breakable).new

          def drain
            first = @buffer.shift
            @buffer.clear
            first.width
          end
        end

        Deque(Breakable).new.storage
        Box.new.drain
      CRYSTAL

      program, analyzer, engine = infer_collection_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "captures explicit returns inside array each blocks" do
      source = <<-'CRYSTAL'
        class Box
          def probe
            [1].each do |x|
              return x
            end
            nil
          end
        end

        if value = Box.new.probe
          value + 1
        else
          0
        end
      CRYSTAL

      program, analyzer, engine = infer_collection_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "supports integer downto blocks when inferring enclosing returns" do
      source = <<-'CRYSTAL'
        class Box
          def probe
            1.downto(0) do |i|
              return i
            end
            nil
          end
        end

        if value = Box.new.probe
          value + 1
        else
          0
        end
      CRYSTAL

      program, analyzer, engine = infer_collection_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "supports nested each plus downto delete_at return corridors" do
      source = <<-'CRYSTAL'
        class Queue
          def deq
            [[1]].each do |gs|
              (gs.size - 1).downto(0) do |i|
                value = gs.delete_at(i)
                return value
              end
            end
            nil
          end
        end

        if value = Queue.new.deq
          value + 1
        else
          0
        end
      CRYSTAL

      program, analyzer, engine = infer_collection_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end

    it "normalizes explicit array element type carriers for nested collections" do
      source = <<-'CRYSTAL'
        class Group
        end

        class Queue
          def initialize
            @queue = [] of Array(Group)
          end

          def seed(group : Group)
            until 0 < @queue.size
              @queue << [] of Group
            end
            @queue[0] << group
          end

          def probe(group : Group)
            seed(group)
            @queue.each do |gs|
              first = gs[0]
              gs.size
              gs.clear
              return first
            end
            nil
          end
        end

        if group = Queue.new.probe(Group.new)
          group.nil? ? 0 : 1
        else
          0
        end
      CRYSTAL

      program, analyzer, engine = infer_collection_builtin_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end
  end
end
