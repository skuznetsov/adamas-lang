require "spec"

require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/identity/def_identity"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

class Adamas::Compiler::Semantic::TypeInferenceEngine
  def __test_validated_selected_def_identity(method : MethodSymbol) : DefIdentity?
    validated_selected_def_identity(method)
  end
end

private def build_selected_def_identity_fixture
  source = <<-CRYSTAL
    class T1Left
      def route(value : Int32) : Int32
        value + 10
      end

      def route(value : String) : Int32
        20
      end
    end

    class T1Right
      def route(value : Int32) : Int32
        value + 30
      end
    end

    left = T1Left.new
    right = T1Right.new
    {left.route(1), left.route("x"), right.route(1)}
  CRYSTAL

  program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
  analyzer = Semantic::Analyzer.new(program)
  analyzer.collect_symbols
  name_result = analyzer.resolve_names
  engine = analyzer.infer_types(name_result.identifier_symbols)

  {program, analyzer, engine}
end

private def route_methods(owner : Semantic::ClassSymbol) : Array(Semantic::MethodSymbol)
  case symbol = owner.scope.lookup("route")
  when Semantic::MethodSymbol
    [symbol]
  when Semantic::OverloadSetSymbol
    symbol.overloads
  else
    raise "route method was not collected"
  end
end

private def route_method_with_arg(
  owner : Semantic::ClassSymbol,
  arg_type : String,
) : Semantic::MethodSymbol
  route_methods(owner).find do |method|
    type_annotation = method.params.first.type_annotation
    type_annotation && String.new(type_annotation) == arg_type
  end || raise "route(#{arg_type}) overload was not collected"
end

describe Semantic::TypeInferenceEngine do
  describe "selected definition identity validation" do
    it "keeps overload and receiver definitions distinct in the owning arena" do
      program, analyzer, engine = build_selected_def_identity_fixture

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty

      table = analyzer.global_context.symbol_table
      left = table.lookup("T1Left").as(Semantic::ClassSymbol)
      right = table.lookup("T1Right").as(Semantic::ClassSymbol)
      left_int = route_method_with_arg(left, "Int32")
      left_string = route_method_with_arg(left, "String")
      right_int = route_method_with_arg(right, "Int32")

      identities = [left_int, left_string, right_int].map do |method|
        engine.__test_validated_selected_def_identity(method).not_nil!
      end

      identities.each(&.arena_id.should(eq(program.ast_arena.object_id.to_u64)))
      identities.map(&.expr_index).uniq.size.should eq(3)
    end

    it "rejects method symbols whose definition payload was detached" do
      _program, analyzer, engine = build_selected_def_identity_fixture
      left = analyzer.global_context.symbol_table.lookup("T1Left").as(Semantic::ClassSymbol)
      method = route_method_with_arg(left, "Int32")

      wrong_name = Semantic::MethodSymbol.new(
        "other",
        method.node_id,
        params: method.params,
        return_annotation: method.return_annotation,
        scope: method.scope,
      )
      copied_params = Semantic::MethodSymbol.new(
        method.name,
        method.node_id,
        params: method.params.dup,
        return_annotation: method.return_annotation,
        scope: method.scope,
      )
      wrong_receiver_kind = Semantic::MethodSymbol.new(
        method.name,
        method.node_id,
        params: method.params,
        return_annotation: method.return_annotation,
        scope: method.scope,
        is_class_method: true,
      )

      engine.__test_validated_selected_def_identity(wrong_name).should be_nil
      engine.__test_validated_selected_def_identity(copied_params).should be_nil
      engine.__test_validated_selected_def_identity(wrong_receiver_kind).should be_nil
    end

    it "fails the live call path closed for a detached selected definition" do
      source = <<-CRYSTAL
        class T1Detached
          def route(value : Int32) : Int32
            value + 1
          end
        end

        T1Detached.new.route(1)
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      owner = analyzer.global_context.symbol_table.lookup("T1Detached").as(Semantic::ClassSymbol)
      method = route_method_with_arg(owner, "Int32")
      detached = Semantic::MethodSymbol.new(
        method.name,
        method.node_id,
        params: method.params.dup,
        return_annotation: method.return_annotation,
        scope: method.scope,
      )
      owner.scope.redefine("route", detached)

      engine = analyzer.infer_types(name_result.identifier_symbols)

      engine.diagnostics.map(&.message).should contain(
        "Selected method 'route' no longer matches its owning definition payload"
      )
      engine.context.get_type(program.roots.last).to_s.should eq("Unknown")
    end
  end
end
