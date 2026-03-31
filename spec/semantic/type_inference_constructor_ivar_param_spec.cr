require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = CrystalV2::Compiler::Frontend
alias Semantic = CrystalV2::Compiler::Semantic

private def infer_constructor_ivar_param_types(source : String)
  parser = Frontend::Parser.new(Frontend::Lexer.new(source))
  program = parser.parse_program

  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

describe Semantic::TypeInferenceEngine do
  describe "constructor ivar params" do
    it "registers typed block ivar params as instance variable types" do
      source = <<-CRYSTAL
        class Worker
          def initialize(&@proc : ->)
          end

          def run
            @proc.call
          end
        end

        Worker.new { nil }.run
      CRYSTAL

      program, analyzer, engine = infer_constructor_ivar_param_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
    end

    it "registers typed block ivar params when initialize is wrapped in a macro body" do
      source = <<-CRYSTAL
        class Context
          def stack_top
            1
          end
        end

        class Stack
          def bottom
            1
          end
        end

        class Fiber
          @context : Context
          @stack : Stack

          {% begin %}
            def initialize(@name : String?, @stack : Stack, &@proc : ->)
              @context = Context.new
            end
          {% end %}

          def run
            @proc.call
          end
        end
      CRYSTAL

      _, analyzer, engine = infer_constructor_ivar_param_types(source)
      fiber_symbol = analyzer.global_context.symbol_table.lookup("Fiber").as(Semantic::ClassSymbol)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      fiber_symbol.get_instance_var_type("proc").should eq("->")
      fiber_symbol.get_instance_var_type("context").should eq("Context")
      fiber_symbol.get_instance_var_type("stack").should eq("Stack")
      engine.diagnostics.should be_empty
    end

    it "registers typed ivar params for nilable flow use" do
      source = <<-CRYSTAL
        class Worker
          def initialize(@name : String?)
          end

          def display
            if name = @name
              name
            else
              "anon"
            end
          end
        end

        Worker.new("sergey").display
      CRYSTAL

      program, analyzer, engine = infer_constructor_ivar_param_types(source)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("String")
    end

    it "preserves ivar metadata across class reopens" do
      source = <<-CRYSTAL
        class Context
          def stack_top
            1
          end
        end

        class Stack
          def bottom
            1
          end
        end

        class Fiber
          @context : Context
          @stack : Stack

          {% begin %}
            def initialize(@name : String?, @stack : Stack, &@proc : ->)
              @context = Context.new
            end
          {% end %}
        end

        class Fiber
          def run
            @proc.call
          end

          def push_gc_roots
            @context.stack_top
            @stack.bottom
          end
        end

        Fiber.new(nil, Stack.new) { nil }.run
      CRYSTAL

      _, analyzer, engine = infer_constructor_ivar_param_types(source)
      fiber_symbol = analyzer.global_context.symbol_table.lookup("Fiber").as(Semantic::ClassSymbol)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      fiber_symbol.get_instance_var_type("proc").should eq("->")
      fiber_symbol.get_instance_var_type("context").should eq("Context")
      fiber_symbol.get_instance_var_type("stack").should eq("Stack")
      engine.diagnostics.should be_empty
    end

    it "backfills untyped ivar params from typed accessors" do
      source = <<-CRYSTAL
        class Worker
          def initialize(@name)
          end

          getter name : String

          def bytesize
            @name.bytesize
          end
        end

        Worker.new("sergey").bytesize
      CRYSTAL

      program, analyzer, engine = infer_constructor_ivar_param_types(source)
      worker_symbol = analyzer.global_context.symbol_table.lookup("Worker").as(Semantic::ClassSymbol)

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      worker_symbol.get_instance_var_type("name").should eq("String")
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
    end
  end
end
