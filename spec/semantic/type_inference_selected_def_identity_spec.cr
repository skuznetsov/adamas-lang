require "spec"

require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/analyzer"
require "../../src/compiler/semantic/identity/def_identity"
require "../../src/compiler/semantic/identity/def_instance_key"
require "../../src/compiler/semantic/type_inference_engine"

alias Frontend = Adamas::Compiler::Frontend
alias Semantic = Adamas::Compiler::Semantic

class Adamas::Compiler::Semantic::TypeInferenceEngine
  def __test_validated_selected_def_identity(method : MethodSymbol) : DefIdentity?
    validated_selected_def_identity(method)
  end

  def __test_local_method_instance_key(
    method : MethodSymbol,
    receiver_type : Type,
    arg_types : Array(Type),
    node : Adamas::Compiler::Frontend::CallNode? = nil,
    block_type : Type? = nil,
    named_arg_types : Hash(String, Type)? = nil,
  ) : DefInstanceKey?
    local_call_resolution(method, receiver_type, arg_types, node, block_type, named_arg_types).try(&.method_instance_key)
  end

  def __test_local_call_resolution_matches_with_key(
    method : MethodSymbol,
    method_instance_key : DefInstanceKey,
    receiver_type : Type,
    arg_types : Array(Type),
    node : Adamas::Compiler::Frontend::CallNode,
    block_type : Type? = nil,
    named_arg_types : Hash(String, Type)? = nil,
  ) : Bool
    resolution = LocalCallResolution.new(method, method_instance_key)
    local_call_resolution_matches?(resolution, receiver_type, arg_types, node, block_type, named_arg_types)
  end

  def __test_infer_local_call_resolution_with_key(
    method : MethodSymbol,
    method_instance_key : DefInstanceKey,
    receiver_type : Type,
    arg_types : Array(Type),
    node : Adamas::Compiler::Frontend::CallNode,
    expr_id : Adamas::Compiler::Frontend::ExprId,
    block_type : Type? = nil,
    named_arg_types : Hash(String, Type)? = nil,
  ) : Type
    resolution = LocalCallResolution.new(method, method_instance_key)
    infer_local_call_resolution_result(resolution, receiver_type, arg_types, node, expr_id, block_type, named_arg_types)
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

    it "types the selected r1-r3 definitions without spelling collisions" do
      _program, analyzer, engine = build_selected_def_identity_fixture
      table = analyzer.global_context.symbol_table
      left = table.lookup("T1Left").as(Semantic::ClassSymbol)
      right = table.lookup("T1Right").as(Semantic::ClassSymbol)
      left_int = route_method_with_arg(left, "Int32")
      left_string = route_method_with_arg(left, "String")
      right_int = route_method_with_arg(right, "Int32")
      int_type = Semantic::PrimitiveType.new("Int32")
      string_type = Semantic::PrimitiveType.new("String")

      r1 = engine.__test_local_method_instance_key(
        left_int,
        Semantic::InstanceType.new(left),
        [int_type] of Semantic::Type,
      ).not_nil!
      r2 = engine.__test_local_method_instance_key(
        left_string,
        Semantic::InstanceType.new(left),
        [string_type] of Semantic::Type,
      ).not_nil!
      r3 = engine.__test_local_method_instance_key(
        right_int,
        Semantic::InstanceType.new(right),
        [int_type] of Semantic::Type,
      ).not_nil!

      r1.def_identity.should_not eq(r2.def_identity)
      r1.def_identity.should_not eq(r3.def_identity)
      r1.receiver_type.should eq(r2.receiver_type)
      r1.receiver_type.should_not eq(r3.receiver_type)
      r1.arg_types.should_not eq(r2.arg_types)
      r1.arg_types.should eq(r3.arg_types)
    end

    it "publishes the selected explicit-receiver target as analysis output" do
      source = <<-CRYSTAL
        class T1PublishedTarget
          def route(value : String) : Int32
            1
          end

          def route(value : Int32) : Int32
            2
          end
        end

        T1PublishedTarget.new.route(1)
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      engine = analyzer.infer_types(name_result.identifier_symbols)
      owner = analyzer.global_context.symbol_table.lookup("T1PublishedTarget").as(Semantic::ClassSymbol)
      method = route_method_with_arg(owner, "Int32")
      call_id = program.roots.last

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      target = engine.context.get_call_target(call_id).not_nil!
      target.def_identity.should eq(engine.__test_validated_selected_def_identity(method))
      target.arg_types.should eq([analyzer.identity_registry.types.primitive("Int32")])
    end

    it "rejects a same-shaped receiver symbol owned by another analyzer" do
      _program, analyzer, engine = build_selected_def_identity_fixture
      _foreign_program, foreign_analyzer, _foreign_engine = build_selected_def_identity_fixture
      left = analyzer.global_context.symbol_table.lookup("T1Left").as(Semantic::ClassSymbol)
      foreign_left = foreign_analyzer.global_context.symbol_table.lookup("T1Left").as(Semantic::ClassSymbol)

      left.node_id.should eq(foreign_left.node_id)
      left.name.should eq(foreign_left.name)
      engine.__test_local_method_instance_key(
        route_method_with_arg(left, "Int32"),
        Semantic::InstanceType.new(foreign_left),
        [Semantic::PrimitiveType.new("Int32")] of Semantic::Type,
      ).should be_nil
    end

    it "accepts a receiver owned below a parent semantic context" do
      source = <<-CRYSTAL
        class LocalOwner
          def route(value : Int32) : Int32
            value
          end
        end

        LocalOwner.new.route(1)
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      parent_table = Semantic::SymbolTable.new
      file_table = Semantic::SymbolTable.new(parent_table)
      analyzer = Semantic::Analyzer.new(program, Semantic::Context.new(file_table))
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      engine = analyzer.infer_types(name_result.identifier_symbols)
      owner = file_table.lookup_local("LocalOwner").as(Semantic::ClassSymbol)

      engine.__test_local_method_instance_key(
        route_method_with_arg(owner, "Int32"),
        Semantic::InstanceType.new(owner),
        [Semantic::PrimitiveType.new("Int32")] of Semantic::Type,
      ).should_not be_nil
    end

    it "accepts the canonical receiver re-exported into the current table" do
      program, analyzer, _engine = build_selected_def_identity_fixture
      owner = analyzer.global_context.symbol_table.lookup("T1Left").as(Semantic::ClassSymbol)
      reexported_table = Semantic::SymbolTable.new
      reexported_table.define(owner.name, owner)
      reexported_engine = Semantic::TypeInferenceEngine.new(
        program,
        {} of Frontend::ExprId => Semantic::Symbol,
        reexported_table,
        identity_registry: analyzer.identity_registry,
      )

      reexported_engine.__test_local_method_instance_key(
        route_method_with_arg(owner, "Int32"),
        Semantic::InstanceType.new(owner),
        [Semantic::PrimitiveType.new("Int32")] of Semantic::Type,
      ).should_not be_nil
    end

    it "keeps one receiver identity across class reopenings" do
      source = <<-CRYSTAL
        class T1Reopened
          def route(value : Int32) : Int32
            value
          end
        end

        class T1Reopened
          def route(value : String) : Int32
            value.size
          end
        end

        reopened = T1Reopened.new
        reopened.route(1)
        reopened.route("x")
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      engine = analyzer.infer_types(name_result.identifier_symbols)
      owner = analyzer.global_context.symbol_table.lookup("T1Reopened").as(Semantic::ClassSymbol)
      int_method = route_method_with_arg(owner, "Int32")
      string_method = route_method_with_arg(owner, "String")

      int_key = engine.__test_local_method_instance_key(
        int_method,
        Semantic::InstanceType.new(owner),
        [Semantic::PrimitiveType.new("Int32")] of Semantic::Type,
      ).not_nil!
      string_key = engine.__test_local_method_instance_key(
        string_method,
        Semantic::InstanceType.new(owner),
        [Semantic::PrimitiveType.new("String")] of Semantic::Type,
      ).not_nil!

      program.roots[0].should_not eq(program.roots[1])
      int_key.receiver_type.should eq(string_key.receiver_type)
      int_key.def_identity.should_not eq(string_key.def_identity)
      engine.diagnostics.should be_empty
    end

    it "rejects stale receiver and method symbols after a shared context is recollected" do
      source = <<-CRYSTAL
        class T1SharedContext
          def route(value : Int32) : Int32
            value
          end
        end
      CRYSTAL

      shared_context = Semantic::Context.new(Semantic::SymbolTable.new)
      first_program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      first_analyzer = Semantic::Analyzer.new(first_program, shared_context)
      first_analyzer.collect_symbols
      first_names = first_analyzer.resolve_names
      first_owner = shared_context.symbol_table.lookup("T1SharedContext").as(Semantic::ClassSymbol)
      first_method = first_owner.scope.lookup("route").as(Semantic::MethodSymbol)
      first_engine = Semantic::TypeInferenceEngine.new(
        first_program,
        first_names.identifier_symbols,
        shared_context.symbol_table,
        identity_registry: first_analyzer.identity_registry,
      )

      second_program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      second_analyzer = Semantic::Analyzer.new(second_program, shared_context)
      second_analyzer.collect_symbols
      second_names = second_analyzer.resolve_names
      second_owner = shared_context.symbol_table.lookup("T1SharedContext").as(Semantic::ClassSymbol)
      second_method = second_owner.scope.lookup("route").as(Semantic::MethodSymbol)
      second_def = second_program.ast_arena[second_method.node_id].as(Frontend::DefNode)
      second_def.params_storage.same?(second_method.params).should be_true
      second_engine = Semantic::TypeInferenceEngine.new(
        second_program,
        second_names.identifier_symbols,
        shared_context.symbol_table,
        identity_registry: second_analyzer.identity_registry,
      )
      arg_types = [Semantic::PrimitiveType.new("Int32")] of Semantic::Type

      first_owner.should_not be(second_owner)
      first_engine.__test_local_method_instance_key(
        first_method,
        Semantic::InstanceType.new(first_owner),
        arg_types,
      ).should be_nil
      second_engine.__test_local_method_instance_key(
        first_method,
        Semantic::InstanceType.new(second_owner),
        arg_types,
      ).should be_nil
      second_engine.__test_local_method_instance_key(
        second_method,
        Semantic::InstanceType.new(second_owner),
        arg_types,
      ).should_not be_nil
    end

    it "rejects a replaced method symbol after the same arena is recollected" do
      source = <<-CRYSTAL
        class T1SameArena
          def route(value : Int32) : Int32
            value
          end
        end

        T1SameArena.new.route(1)
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      first_names = analyzer.resolve_names
      first_owner = analyzer.global_context.symbol_table.lookup("T1SameArena").as(Semantic::ClassSymbol)
      first_method = first_owner.scope.lookup("route").as(Semantic::MethodSymbol)
      arg_types = [Semantic::PrimitiveType.new("Int32")] of Semantic::Type
      first_engine = analyzer.infer_types(first_names.identifier_symbols)
      first_key = first_engine.__test_local_method_instance_key(
        first_method,
        Semantic::InstanceType.new(first_owner),
        arg_types,
      ).not_nil!

      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      second_owner = analyzer.global_context.symbol_table.lookup("T1SameArena").as(Semantic::ClassSymbol)
      second_method = second_owner.scope.lookup("route").as(Semantic::MethodSymbol)
      engine = analyzer.infer_types(name_result.identifier_symbols)
      call_id = program.roots.last
      call_node = program.ast_arena[call_id].as(Frontend::CallNode)

      first_owner.should_not be(second_owner)
      first_method.should_not be(second_method)
      engine.__test_validated_selected_def_identity(first_method).should_not be_nil
      {
        key: engine.__test_local_method_instance_key(
          first_method,
          Semantic::InstanceType.new(second_owner),
          arg_types,
        ),
        consumer_accepts: engine.__test_local_call_resolution_matches_with_key(
          first_method,
          first_key,
          Semantic::InstanceType.new(second_owner),
          arg_types,
          call_node,
        ),
      }.should eq({key: nil, consumer_accepts: false})
      engine.__test_local_method_instance_key(
        second_method,
        Semantic::InstanceType.new(second_owner),
        arg_types,
      ).should_not be_nil
    end

    it "accepts current inherited and included methods from their declaring scopes" do
      source = <<-CRYSTAL
        module T1IncludedRoute
          def included_route(value : String) : Int32
            value.size
          end
        end

        class T1ParentRoute
          def inherited_route(value : Int32) : Int32
            value
          end
        end

        class T1ChildRoute < T1ParentRoute
          include T1IncludedRoute
        end
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      engine = analyzer.infer_types(name_result.identifier_symbols)
      table = analyzer.global_context.symbol_table
      included_owner = table.lookup("T1IncludedRoute").as(Semantic::ModuleSymbol)
      parent_owner = table.lookup("T1ParentRoute").as(Semantic::ClassSymbol)
      child_owner = table.lookup("T1ChildRoute").as(Semantic::ClassSymbol)
      included_method = included_owner.scope.lookup("included_route").as(Semantic::MethodSymbol)
      inherited_method = parent_owner.scope.lookup("inherited_route").as(Semantic::MethodSymbol)
      receiver_type = Semantic::InstanceType.new(child_owner)

      engine.__test_local_method_instance_key(
        inherited_method,
        receiver_type,
        [Semantic::PrimitiveType.new("Int32")] of Semantic::Type,
      ).should_not be_nil
      engine.__test_local_method_instance_key(
        included_method,
        receiver_type,
        [Semantic::PrimitiveType.new("String")] of Semantic::Type,
      ).should_not be_nil
    end

    it "keeps same-named nested receiver declarations distinct" do
      source = <<-CRYSTAL
        module LeftOwner
          class Thing
            def route(value : Int32) : Int32
              value
            end
          end
        end

        module RightOwner
          class Thing
            def route(value : Int32) : Int32
              value
            end
          end
        end
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      engine = analyzer.infer_types(name_result.identifier_symbols)
      table = analyzer.global_context.symbol_table
      left_owner = table.lookup("LeftOwner").as(Semantic::ModuleSymbol)
      right_owner = table.lookup("RightOwner").as(Semantic::ModuleSymbol)
      left = left_owner.scope.lookup("Thing").as(Semantic::ClassSymbol)
      right = right_owner.scope.lookup("Thing").as(Semantic::ClassSymbol)
      arg_types = [Semantic::PrimitiveType.new("Int32")] of Semantic::Type

      left_key = engine.__test_local_method_instance_key(
        route_method_with_arg(left, "Int32"),
        Semantic::InstanceType.new(left),
        arg_types,
      ).not_nil!
      right_key = engine.__test_local_method_instance_key(
        route_method_with_arg(right, "Int32"),
        Semantic::InstanceType.new(right),
        arg_types,
      ).not_nil!

      left_key.receiver_type.should_not eq(right_key.receiver_type)
    end

    it "does not mint an unresolved generic receiver identity" do
      source = <<-CRYSTAL
        class T1Generic(T)
          def route(value : Int32) : Int32
            value
          end
        end

        class T1MethodGeneric
          def route(value : U) : U forall U
            value
          end
        end

        T1MethodGeneric.new.route(1)
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      engine = Semantic::TypeInferenceEngine.new(
        program,
        name_result.identifier_symbols,
        analyzer.global_context.symbol_table,
        identity_registry: analyzer.identity_registry,
      )
      owner = analyzer.global_context.symbol_table.lookup("T1Generic").as(Semantic::ClassSymbol)
      method_owner = analyzer.global_context.symbol_table.lookup("T1MethodGeneric").as(Semantic::ClassSymbol)
      method = route_methods(method_owner).first
      call_id = program.roots.last
      call_node = program.ast_arena[call_id].as(Frontend::CallNode)
      int_type = Semantic::PrimitiveType.new("Int32")

      engine.__test_local_method_instance_key(
        route_method_with_arg(owner, "Int32"),
        Semantic::InstanceType.new(owner),
        [Semantic::PrimitiveType.new("Int32")] of Semantic::Type,
      ).should be_nil
      engine.__test_local_method_instance_key(
        method,
        Semantic::InstanceType.new(method_owner),
        [int_type] of Semantic::Type,
      ).should be_nil

      method_identity = engine.__test_validated_selected_def_identity(method).not_nil!
      receiver_identity = Semantic::DefIdentity.new(program.ast_arena.object_id.to_u64, method_owner.node_id.index)
      fabricated_key = Semantic::DefInstanceKey.new(
        def_identity: method_identity,
        receiver_type: analyzer.identity_registry.types.nominal("T1MethodGeneric", Semantic::TypeKind::Class, receiver_identity),
        arg_types: [analyzer.identity_registry.types.primitive("Int32")],
      )
      engine.__test_local_call_resolution_matches_with_key(
        method,
        fabricated_key,
        Semantic::InstanceType.new(method_owner),
        [int_type] of Semantic::Type,
        call_node,
      ).should be_false
    end

    it "keys and validates the r4 block result and single r5 named argument" do
      source = <<-CRYSTAL
        class T1Block
          def route(value : Int32, &block : Int32 -> Int32) : Int32
            yield value
          end
        end

        class T1Named
          def route(*, level : Int32) : Int32
            level
          end
        end

        T1Block.new.route(2) { |value| value + 1 }
        T1Named.new.route(level: 3)
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      guard_engine = Semantic::TypeInferenceEngine.new(
        program,
        name_result.identifier_symbols,
        analyzer.global_context.symbol_table,
        identity_registry: analyzer.identity_registry,
      )
      engine = analyzer.infer_types(name_result.identifier_symbols)
      table = analyzer.global_context.symbol_table
      block_owner = table.lookup("T1Block").as(Semantic::ClassSymbol)
      named_owner = table.lookup("T1Named").as(Semantic::ClassSymbol)
      block_method = route_method_with_arg(block_owner, "Int32")
      named_method = route_methods(named_owner).first
      block_call = program.ast_arena[program.roots[-2]].as(Frontend::CallNode)
      named_call = program.ast_arena[program.roots.last].as(Frontend::CallNode)
      int_type = Semantic::PrimitiveType.new("Int32")
      named_types = {
        "level" => int_type.as(Semantic::Type),
      }

      analyzer.semantic_diagnostics.should be_empty
      analyzer.name_resolver_diagnostics.should be_empty
      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots[-2]).to_s.should eq("Int32")
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")

      block_key = guard_engine.__test_local_method_instance_key(
        block_method,
        Semantic::InstanceType.new(block_owner),
        [int_type] of Semantic::Type,
        block_call,
        int_type,
      ).not_nil!
      named_key = guard_engine.__test_local_method_instance_key(
        named_method,
        Semantic::InstanceType.new(named_owner),
        [] of Semantic::Type,
        named_call,
        named_arg_types: named_types,
      ).not_nil!

      block_key.block_type.should_not be_nil
      block_key.named_arg_types.should be_nil
      named_key.block_type.should be_nil
      named_key.arg_types.should be_empty
      named_entries = named_key.named_arg_types.not_nil!
      named_entries.map { |entry| analyzer.identity_registry.lookup_name(entry[0]).not_nil! }.should eq(["level"])

      guard_engine.__test_local_call_resolution_matches_with_key(
        block_method,
        block_key,
        Semantic::InstanceType.new(block_owner),
        [int_type] of Semantic::Type,
        block_call,
        int_type,
      ).should be_true
      guard_engine.__test_local_call_resolution_matches_with_key(
        named_method,
        named_key,
        Semantic::InstanceType.new(named_owner),
        [] of Semantic::Type,
        named_call,
        named_arg_types: named_types,
      ).should be_true

      wrong_block_key = Semantic::DefInstanceKey.new(
        def_identity: block_key.def_identity,
        receiver_type: block_key.receiver_type,
        arg_types: block_key.arg_types,
        block_type: analyzer.identity_registry.types.primitive("String"),
      )
      wrong_named_key = Semantic::DefInstanceKey.new(
        def_identity: named_key.def_identity,
        receiver_type: named_key.receiver_type,
        named_arg_types: [{analyzer.identity_registry.intern_name("other"), named_entries.first[1]}],
      )

      guard_engine.__test_local_call_resolution_matches_with_key(
        block_method,
        wrong_block_key,
        Semantic::InstanceType.new(block_owner),
        [int_type] of Semantic::Type,
        block_call,
        int_type,
      ).should be_false
      guard_engine.__test_local_call_resolution_matches_with_key(
        named_method,
        wrong_named_key,
        Semantic::InstanceType.new(named_owner),
        [] of Semantic::Type,
        named_call,
        named_arg_types: named_types,
      ).should be_false

      guard_engine.__test_infer_local_call_resolution_with_key(
        block_method,
        wrong_block_key,
        Semantic::InstanceType.new(block_owner),
        [int_type] of Semantic::Type,
        block_call,
        program.roots[-2],
        int_type,
      ).to_s.should eq("Unknown")
      guard_engine.__test_infer_local_call_resolution_with_key(
        named_method,
        wrong_named_key,
        Semantic::InstanceType.new(named_owner),
        [] of Semantic::Type,
        named_call,
        program.roots.last,
        named_arg_types: named_types,
      ).to_s.should eq("Unknown")
      guard_engine.diagnostics.map(&.message).should eq([
        "Typed call resolution no longer matches the selected method or call shape",
        "Typed call resolution no longer matches the selected method or call shape",
      ])
    end

    it "leaves defaulted named calls on the legacy path" do
      source = <<-CRYSTAL
        class T1NamedDefault
          def route(*, level : Int32 = 1) : Int32
            level
          end
        end

        T1NamedDefault.new.route(level: 2)
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      engine = analyzer.infer_types(name_result.identifier_symbols)
      owner = analyzer.global_context.symbol_table.lookup("T1NamedDefault").as(Semantic::ClassSymbol)
      method = route_methods(owner).first
      call_id = program.roots.last
      call_node = program.ast_arena[call_id].as(Frontend::CallNode)
      named_types = {"level" => Semantic::PrimitiveType.new("Int32").as(Semantic::Type)}

      engine.__test_local_method_instance_key(
        method,
        Semantic::InstanceType.new(owner),
        [] of Semantic::Type,
        call_node,
        named_arg_types: named_types,
      ).should be_nil
      engine.diagnostics.should be_empty
      engine.context.get_type(call_id).to_s.should eq("Int32")
      engine.context.get_call_target(call_id).should be_nil
    end

    it "does not classify a pre-separator parameter as named-only" do
      source = <<-CRYSTAL
        class T1NamedBeforeSeparator
          def route(level : Int32, *) : Int32
            level
          end
        end

        T1NamedBeforeSeparator.new.route(level: 2)
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      engine = analyzer.infer_types(name_result.identifier_symbols)
      owner = analyzer.global_context.symbol_table.lookup("T1NamedBeforeSeparator").as(Semantic::ClassSymbol)
      method = route_methods(owner).first
      call_id = program.roots.last
      call_node = program.ast_arena[call_id].as(Frontend::CallNode)
      named_types = {"level" => Semantic::PrimitiveType.new("Int32").as(Semantic::Type)}

      engine.__test_local_method_instance_key(
        method,
        Semantic::InstanceType.new(owner),
        [] of Semantic::Type,
        call_node,
        named_arg_types: named_types,
      ).should be_nil
      engine.diagnostics.should be_empty
      engine.context.get_type(call_id).to_s.should eq("Int32")
    end

    it "leaves optional positional block calls on the legacy path" do
      source = <<-CRYSTAL
        class T1BlockDefault
          def route(value : Int32 = 1, &block : Int32 -> Int32) : Int32
            yield value
          end
        end

        T1BlockDefault.new.route { |value| value }
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      engine = analyzer.infer_types(name_result.identifier_symbols)
      owner = analyzer.global_context.symbol_table.lookup("T1BlockDefault").as(Semantic::ClassSymbol)
      method = route_methods(owner).first
      call_id = program.roots.last
      call_node = program.ast_arena[call_id].as(Frontend::CallNode)

      engine.__test_local_method_instance_key(
        method,
        Semantic::InstanceType.new(owner),
        [] of Semantic::Type,
        call_node,
        Semantic::PrimitiveType.new("Int32"),
      ).should be_nil
      engine.diagnostics.should be_empty
      engine.context.get_type(call_id).to_s.should eq("Int32")
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

    it "does not confuse a synthetic builtin with definition zero" do
      source = <<-CRYSTAL
        class Hash(K, V)
          def initialize
          end

          def fetch(key : K)
            yield
          end
        end

        Hash(String, Int32).new.fetch("x") { 1 }
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      program.ast_arena[Frontend::ExprId.new(0)].should be_a(Frontend::DefNode)
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      engine = analyzer.infer_types(name_result.identifier_symbols)

      engine.diagnostics.should be_empty
      engine.context.get_type(program.roots.last).to_s.should eq("Int32")
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

    it "fails the live named-call path closed for a detached selected definition" do
      source = <<-CRYSTAL
        class T1NamedDetached
          def route(*, level : Int32) : Int32
            level
          end
        end

        T1NamedDetached.new.route(level: 1)
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      owner = analyzer.global_context.symbol_table.lookup("T1NamedDetached").as(Semantic::ClassSymbol)
      method = route_methods(owner).first
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

    it "rejects a mismatched typed key before method body inference" do
      source = <<-CRYSTAL
        class T1TypedMismatch
          def route(value : Int32)
            "x" + value
          end
        end

        T1TypedMismatch.new.route(1)
        T1TypedMismatch.new.route(value: 1)
      CRYSTAL

      program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
      analyzer = Semantic::Analyzer.new(program)
      analyzer.collect_symbols
      name_result = analyzer.resolve_names
      owner = analyzer.global_context.symbol_table.lookup("T1TypedMismatch").as(Semantic::ClassSymbol)
      method = route_method_with_arg(owner, "Int32")
      receiver_type = Semantic::InstanceType.new(owner)
      arg_types = [Semantic::PrimitiveType.new("Int32")] of Semantic::Type
      engine = Semantic::TypeInferenceEngine.new(
        program,
        name_result.identifier_symbols,
        analyzer.global_context.symbol_table,
        identity_registry: analyzer.identity_registry,
      )
      valid_key = engine.__test_local_method_instance_key(method, receiver_type, arg_types).not_nil!
      wrong_key = Semantic::DefInstanceKey.new(
        def_identity: Semantic::DefIdentity.new(valid_key.def_identity.arena_id, valid_key.def_identity.expr_index + 1),
        receiver_type: valid_key.receiver_type,
        arg_types: valid_key.arg_types,
      )
      call_id = program.roots[-2]
      call_node = program.ast_arena[call_id].as(Frontend::CallNode)

      result = engine.__test_infer_local_call_resolution_with_key(
        method,
        wrong_key,
        receiver_type,
        arg_types,
        call_node,
        call_id,
      )
      named_call_id = program.roots.last
      named_call_node = program.ast_arena[named_call_id].as(Frontend::CallNode)
      named_result = engine.__test_infer_local_call_resolution_with_key(
        method,
        valid_key,
        receiver_type,
        arg_types,
        named_call_node,
        named_call_id,
      )

      result.to_s.should eq("Unknown")
      named_result.to_s.should eq("Unknown")
      engine.diagnostics.map(&.message).should eq([
        "Typed call resolution no longer matches the selected method or call shape",
        "Typed call resolution no longer matches the selected method or call shape",
      ])
    end
  end
end
