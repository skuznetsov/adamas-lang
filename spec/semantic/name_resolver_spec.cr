require "spec"
require "./ast_fixtures"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/semantic/analyzer"

module NameResolverSpecAliases
  alias Frontend = CrystalV2::Compiler::Frontend
  alias Semantic = CrystalV2::Compiler::Semantic
end

include NameResolverSpecAliases

private def test_span
  Frontend::Span.new(0, 0, 1, 1, 1, 1)
end

describe Semantic::NameResolver do
  it "resolves identifiers to macro symbols" do
    arena = Frontend::AstArena.new

    body_id = arena.add(Frontend::MacroLiteralNode.new(
      test_span,
      [] of Frontend::MacroPiece,
      false,
      false
    ))

    macro_id = arena.add(Frontend::MacroDefNode.new(
      test_span,
      "greet".to_slice,
      body_id
    ))

    callee_id = arena.add(Frontend::IdentifierNode.new(
      test_span,
      "greet".to_slice
    ))

    call_id = arena.add(Frontend::CallNode.new(
      test_span,
      callee_id,
      [] of Frontend::ExprId
    ))

    program = Frontend::Program.new(arena, [macro_id, call_id])
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
    result.identifier_symbols[callee_id].should be_a(Semantic::MacroSymbol)
  end

  it "resolves bare macro identifiers at the root level" do
    arena = Frontend::AstArena.new

    body_id = arena.add(Frontend::MacroLiteralNode.new(
      test_span,
      [] of Frontend::MacroPiece,
      false,
      false
    ))

    macro_id = arena.add(Frontend::MacroDefNode.new(
      test_span,
      "define_alpha".to_slice,
      body_id
    ))

    root_macro_call = arena.add(Frontend::IdentifierNode.new(
      test_span,
      "define_alpha".to_slice
    ))

    program = Frontend::Program.new(arena, [macro_id, root_macro_call])
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
    result.identifier_symbols[root_macro_call].should be_a(Semantic::MacroSymbol)
  end

  it "resolves macros inherited through the class hierarchy in class bodies" do
    source = <<-CR
      class Object
        macro def_hash(*fields)
          def hash(hasher)
            {% for field in fields %}
              hasher = {{field.id}}.hash(hasher)
            {% end %}
            hasher
          end
        end
      end

      class Reference < Object
      end

      class Box < Reference
        def initialize(@x : Int32)
        end

        def_hash @x
      end
    CR

    lexer = Frontend::Lexer.new(source)
    parser = Frontend::Parser.new(lexer)
    program = parser.parse_program

    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "emits diagnostics for undefined identifiers" do
    arena = Frontend::AstArena.new

    callee_id = arena.add(Frontend::IdentifierNode.new(
      test_span,
      "missing".to_slice
    ))

    call_id = arena.add(Frontend::CallNode.new(
      test_span,
      callee_id,
      [] of Frontend::ExprId
    ))

    program = Frontend::Program.new(arena, [call_id])
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.identifier_symbols.should be_empty
    result.diagnostics.size.should eq(1)
    result.diagnostics.first.message.should eq("undefined local variable or method 'missing'")
  end

  it "emits diagnostics for unresolved bare receiverless sends inside method bodies" do
    source = <<-CR
      class Box
        def run
          missing
        end
      end
    CR

    lexer = Frontend::Lexer.new(source)
    parser = Frontend::Parser.new(lexer)
    program = parser.parse_program

    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.size.should eq(1)
    result.diagnostics.first.message.should eq("undefined local variable or method 'missing'")
  end

  it "defers unresolved bare receiverless sends inside method bodies when explicitly enabled" do
    source = <<-CR
      class Box
        def run
          missing
        end
      end
    CR

    lexer = Frontend::Lexer.new(source)
    parser = Frontend::Parser.new(lexer)
    program = parser.parse_program

    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names(defer_method_body_receiverless_candidates: true)

    result.diagnostics.should be_empty
  end

  it "defers unresolved receiverless identifiers nested inside method-body expressions when explicitly enabled" do
    source = <<-CR
      class Box
        def run
          missing + 1
        end
      end
    CR

    lexer = Frontend::Lexer.new(source)
    parser = Frontend::Parser.new(lexer)
    program = parser.parse_program

    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names(defer_method_body_receiverless_candidates: true)

    result.diagnostics.should be_empty
  end

  it "emits diagnostics for unresolved identifiers nested inside method-body expressions" do
    source = <<-CR
      class Box
        def run
          missing + 1
        end
      end
    CR

    lexer = Frontend::Lexer.new(source)
    parser = Frontend::Parser.new(lexer)
    program = parser.parse_program

    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.size.should eq(1)
    result.diagnostics.first.message.should eq("undefined local variable or method 'missing'")
  end

  it "ignores numeric identifiers inside type-expression generic args" do
    source = <<-CR
      class Box
        def run
          uninitialized UInt8[4]
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "ignores parser-stored typeof identifiers inside generic type arguments" do
    source = <<-CR
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
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves method parameters within method scope" do
    arena = Frontend::AstArena.new

    param_ref = AstFixtures.make_identifier(arena, "name")
    method_id = AstFixtures.make_def(arena, "greet", params: ["name"], body: [param_ref])

    program = Frontend::Program.new(arena, [method_id])
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
    result.identifier_symbols[param_ref].should be_a(Semantic::VariableSymbol)
  end

  it "resolves method calls within class scope" do
    arena = Frontend::AstArena.new

    greet_method = AstFixtures.make_def(arena, "greet")
    call_id = AstFixtures.make_call(arena, "greet")
    call_node = arena[call_id]
    call_node.should be_a(Frontend::CallNode)
    callee_id = call_node.as(Frontend::CallNode).callee
    say_hello = AstFixtures.make_def(arena, "say_hello", body: [call_id])
    class_id = AstFixtures.make_class(arena, "Greeter", body: [greet_method, say_hello])

    program = Frontend::Program.new(arena, [class_id])
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
    result.identifier_symbols[callee_id].should be_a(Semantic::MethodSymbol)
  end

  it "resolves locals introduced inside responds_to? receivers" do
    source = <<-CR
      class Host
        def sample(probe)
          if (gc = probe).responds_to?(:sig_suspend)
            gc
          end
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves locals introduced inside is_a? receivers" do
    source = <<-CR
      class Host
        def sample(current)
          return nil if (c = current).is_a?(Nil)
          c
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves module-body implicit self requirements through includers" do
    source = <<-CR
      module NeedsFd
        def blocking?
          fd
        end
      end

      class Host
        include NeedsFd

        def fd
          1
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty

    needs_fd = program.arena[program.roots.first].as(Frontend::ModuleNode)
    blocking = program.arena[needs_fd.body.not_nil!.first].as(Frontend::DefNode)
    fd_ref = blocking.body.not_nil!.first

    result.identifier_symbols[fd_ref].should be_a(Semantic::MethodSymbol)
    result.identifier_symbols[fd_ref].name.should eq("fd")
  end

  it "resolves receiverless calls to class-body macro-generated methods" do
    source = <<-CR
      class Flags
        {% for flag in [:undf, :abs] %}
          def {{flag.id}}?
            true
          end
        {% end %}

        def sample
          undf? && abs?
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves block params referenced inside yield arguments" do
    source = <<-CR
      module U
        def self.outer(& : Char ->)
          inner { |x| yield x.unsafe_chr }
        end

        private def self.inner(& : Int32 ->)
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty

    mod = program.arena[program.roots.first].as(Frontend::ModuleNode)
    outer = program.arena[mod.body.not_nil!.first].as(Frontend::DefNode)
    inner_call = program.arena[outer.body.not_nil!.first].as(Frontend::CallNode)
    block_id = inner_call.block || inner_call.args.find { |arg_id| program.arena[arg_id].is_a?(Frontend::BlockNode) }
    block_id.should_not be_nil

    block = program.arena[block_id.not_nil!].as(Frontend::BlockNode)
    yield_node = program.arena[block.body.first].as(Frontend::YieldNode)
    member_access = program.arena[yield_node.args.not_nil!.first].as(Frontend::MemberAccessNode)
    x_ref = member_access.object

    result.identifier_symbols[x_ref].should be_a(Semantic::VariableSymbol)
    result.identifier_symbols[x_ref].name.should eq("x")
  end

  it "resolves absolute class reopens against the root scope" do
    source = <<-CR
      class RootTarget
        def marker
          1
        end
      end

      module Outer
        class ::RootTarget
          def again
            marker
          end
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty

    outer = program.arena[program.roots[1]].as(Frontend::ModuleNode)
    reopened = program.arena[outer.body.not_nil!.first].as(Frontend::ClassNode)
    again_def = program.arena[reopened.body.not_nil!.first].as(Frontend::DefNode)
    marker_ref = again_def.body.not_nil!.first

    result.identifier_symbols[marker_ref].should be_a(Semantic::MethodSymbol)
    result.identifier_symbols[marker_ref].name.should eq("marker")
  end

  it "resolves calls to top-level fun declarations" do
    source = <<-CR
      fun __crystal_raise(unwind_ex : Void*) : NoReturn

      def raise_without_backtrace(exception)
        __crystal_raise(exception.as(Void*))
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty

    def_node = program.arena[program.roots[1]].as(Frontend::DefNode)
    call_node = program.arena[def_node.body.not_nil!.first].as(Frontend::CallNode)
    callee_id = call_node.callee

    result.identifier_symbols[callee_id].should be_a(Semantic::MethodSymbol)
    result.identifier_symbols[callee_id].name.should eq("__crystal_raise")
  end

  it "resolves macro-generated fun bodies with ternary-generated names" do
    source = <<-CR
      macro define_personality(mingw)
        fun {{ mingw ? "__crystal_personality_imp".id : "__crystal_personality".id }}(
          context : Void*
        ) : Int32
          context.address
          1
        end
      end

      define_personality(false)
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    analyzer.semantic_diagnostics.should be_empty
    result.diagnostics.should be_empty
    analyzer.global_context.symbol_table.lookup("__crystal_personality").should be_a(Semantic::MethodSymbol)
  end

  it "resolves parameters inside top-level fun bodies that start with macro control" do
    source = <<-CR
      fun __crystal_malloc64(size : UInt64) : UInt64
        {% if flag?(:bits32) %}
          size
        {% end %}

        size
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty

    def_node = program.arena[program.roots[0]].as(Frontend::DefNode)
    result.identifier_symbols[def_node.body.not_nil!.last].should be_a(Semantic::VariableSymbol)
    result.identifier_symbols[def_node.body.not_nil!.last].name.should eq("size")
  end

  it "resolves nested enums referenced later in the same class body" do
    source = <<-CR
      struct Path
        enum Kind
          POSIX
          WINDOWS

          def self.native
            POSIX
          end
        end

        def self.separators(kind)
          kind
        end

        SEPARATORS = separators(Kind.native)
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty

    path_symbol = analyzer.global_context.symbol_table.lookup("Path").as(Semantic::ClassSymbol)
    path_symbol.scope.lookup_local("Kind").should be_a(Semantic::EnumSymbol)
  end

  it "resolves locals introduced by multiple assignment" do
    arena = Frontend::AstArena.new

    first_target = AstFixtures.make_identifier(arena, "found")
    second_target = AstFixtures.make_identifier(arena, "value")
    tuple_id = arena.add(Frontend::TupleLiteralNode.new(
      test_span,
      [AstFixtures.make_number(arena, 1), AstFixtures.make_number(arena, 2)]
    ))
    assign_id = arena.add(Frontend::MultipleAssignNode.new(
      test_span,
      [first_target, second_target],
      tuple_id
    ))

    first_ref = AstFixtures.make_identifier(arena, "found")
    second_ref = AstFixtures.make_identifier(arena, "value")
    method_id = AstFixtures.make_def(arena, "sample", body: [assign_id, first_ref, second_ref])

    program = Frontend::Program.new(arena, [method_id])
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
    result.identifier_symbols[first_ref].should be_a(Semantic::VariableSymbol)
    result.identifier_symbols[second_ref].should be_a(Semantic::VariableSymbol)
  end

  it "ignores brace tuple type identifiers in generic type expressions" do
    source = <<-CR
      class Array(T)
      end

      value = Array({UInt64, UInt64, UInt64})
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves locals introduced by splatted multiple assignment targets" do
    source = <<-CR
      def sample(segments)
        first, *rest = segments
        first
        rest
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty

    method_node = program.arena[program.roots.first].as(Frontend::DefNode)
    body = method_node.body.not_nil!
    first_ref = body[1]
    rest_ref = body[2]

    result.identifier_symbols[first_ref].should be_a(Semantic::VariableSymbol)
    result.identifier_symbols[rest_ref].should be_a(Semantic::VariableSymbol)
  end

  it "resolves locals introduced by type declarations" do
    arena = Frontend::AstArena.new

    decl_id = arena.add(Frontend::TypeDeclarationNode.new(
      test_span,
      "quote".to_slice,
      "Char?".to_slice,
      arena.add(Frontend::NilNode.new(test_span))
    ))
    ref_id = AstFixtures.make_identifier(arena, "quote")
    method_id = AstFixtures.make_def(arena, "sample", body: [decl_id, ref_id])

    program = Frontend::Program.new(arena, [method_id])
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
    result.identifier_symbols[ref_id].should be_a(Semantic::VariableSymbol)
  end

  it "resolves locals introduced by out arguments" do
    source = <<-CR
      lib LibC
        fun getrusage(which : Int32, usage : Int32*)
      end

      def sample
        LibC.getrusage(0, out usage)
        usage
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves class method bodies through class scope" do
    arena = Frontend::AstArena.new

    call_id = AstFixtures.make_call(arena, "greet")
    call_node = arena[call_id]
    call_node.should be_a(Frontend::CallNode)
    callee_id = call_node.as(Frontend::CallNode).callee

    class_greet = AstFixtures.make_def(arena, "greet", receiver: "self")
    class_call = AstFixtures.make_def(arena, "call", body: [call_id], receiver: "self")
    class_id = AstFixtures.make_class(arena, "Greeter", body: [class_greet, class_call])

    program = Frontend::Program.new(arena, [class_id])
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
    result.identifier_symbols[callee_id].should be_a(Semantic::MethodSymbol)
  end

  it "resolves nested constants from class method scope" do
    arena = Frontend::AstArena.new

    nested_class_id = arena.add(Frontend::VisibilityModifierNode.new(
      test_span,
      Frontend::Visibility::Private,
      AstFixtures.make_class(arena, "ParsedUnit")
    ))
    constant_ref = AstFixtures.make_identifier(arena, "ParsedUnit")
    new_call_callee = arena.add(Frontend::MemberAccessNode.new(
      test_span,
      constant_ref,
      "new".to_slice
    ))
    new_call_id = arena.add(Frontend::CallNode.new(
      test_span,
      new_call_callee,
      [] of Frontend::ExprId
    ))
    build_id = AstFixtures.make_def(arena, "build", body: [new_call_id], receiver: "self")
    outer_class_id = AstFixtures.make_class(arena, "CLI", body: [nested_class_id, build_id])

    program = Frontend::Program.new(arena, [outer_class_id])
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
    result.identifier_symbols[constant_ref].should be_a(Semantic::ClassSymbol)
  end

  it "resolves enum members referenced by later enum values" do
    source = <<-CR
      enum WinError : UInt32
        WSABASEERR = 10000_u32
        WSAEINTR = WSABASEERR + 4
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty

    enum_node = program.arena[program.roots.first].as(Frontend::EnumNode)
    member_value = enum_node.members[1].value.not_nil!
    binary = program.arena[member_value].as(Frontend::BinaryNode)
    enum_ref = binary.left

    result.identifier_symbols[enum_ref].should be_a(Semantic::ConstantSymbol)
  end

  it "resolves implicit constructor calls in class body constants" do
    source = <<-CR
      class Box
        INSTANCE = new
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty

    class_node = program.arena[program.roots.first].as(Frontend::ClassNode)
    constant_node = program.arena[class_node.body.not_nil!.first].as(Frontend::ConstantNode)
    identifier_id = constant_node.value
    program.arena[identifier_id].should be_a(Frontend::IdentifierNode)

    result.identifier_symbols[identifier_id].should be_a(Semantic::MethodSymbol)
    result.identifier_symbols[identifier_id].as(Semantic::MethodSymbol).name.should eq("new")
  end

  it "prefers root class constants over included module namespace siblings in method bodies" do
    source = <<-CR
      module Crystal::System::Fiber
      end

      module Crystal::System::Thread
      end

      class Fiber
        def self.inactive(fiber : Fiber)
        end
      end

      class Thread
        include Crystal::System::Thread

        def finish(fiber : Fiber)
          Fiber.inactive(fiber)
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty

    thread_node = program.arena[program.roots.last].as(Frontend::ClassNode)
    finish_node = program.arena[thread_node.body.not_nil!.last].as(Frontend::DefNode)
    call_node = program.arena[finish_node.body.not_nil!.first].as(Frontend::CallNode)
    callee = program.arena[call_node.callee].as(Frontend::MemberAccessNode)
    fiber_ref = callee.object

    result.identifier_symbols[fiber_ref].should be_a(Semantic::ClassSymbol)
    result.identifier_symbols[fiber_ref].as(Semantic::ClassSymbol).name.should eq("Fiber")
  end

  it "ignores source macro expressions during name resolution" do
    source = <<-CR
      {% skip_file unless flag?(:wasi) %}
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves class constants and aliases inside method bodies" do
    source = <<-CR
      module Crystal::HIR
        class Foo
          BAR = 1
          alias Baz = Int32

          def test
            BAR
            Baz
          end
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves locals assigned inside begin blocks after the block" do
    source = <<-CR
      def sample
        begin
          value = 1
        ensure
          2
        end
        value
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves inherited receiverless calls through the superclass chain" do
    source = <<-CR
      class Parent
        def dup
          1
        end
      end

      class Child < Parent
        def sample
          dup
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves module-body implicit self requirements through scoped includer superclasses" do
    source = <<-CR
      module IO
        class FileDescriptor
          def fd
            1
          end
        end
      end

      module NeedsFd
        def blocking?
          fd
        end
      end

      class Host < IO::FileDescriptor
        include NeedsFd
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves generic type parameters inside class methods" do
    source = <<-CR
      struct SmallDeque(T, N)
        def capacity
          N
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves magic compile-time constants" do
    source = <<-CR
      def sample(file = __FILE__, line = __LINE__, dir = __DIR__)
        {file, line, dir}
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "keeps bootstrap argv unsafe globals green through type inference" do
    source = <<-CR
      def sample(i : Int32)
        ARGV_UNSAFE.value
        ARGC_UNSAFE - 1
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names
    analyzer.infer_types(result.identifier_symbols)

    result.diagnostics.should be_empty
    analyzer.type_inference_diagnostics.should be_empty
  end

  it "resolves top-level funs guarded by unless flag macros" do
    source = <<-CR
      {% unless flag?(:interpreted) %}
        fun __crystal_raise(unwind_ex : Void*) : NoReturn
        end
      {% end %}

      def raise_without_backtrace(exception)
        __crystal_raise(exception.as(Void*))
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names
    analyzer.infer_types(result.identifier_symbols)

    result.diagnostics.should be_empty
    analyzer.type_inference_diagnostics.should be_empty
  end

  it "resolves identifiers inside slice indexes before class method calls" do
    source = <<-CR
      class Time
        class Location
          def self.load(name : String) : Location
            new
          end
        end
      end

      def test(realpath : String, pos : Int32)
        name = realpath[(pos + "zoneinfo/".size)..]
        ::Time::Location.load(name)
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names
    analyzer.infer_types(result.identifier_symbols)

    result.diagnostics.should be_empty
    analyzer.type_inference_diagnostics.should be_empty
  end

  it "keeps proc pointer target type arguments green through type inference" do
    source = <<-CR
      class Thread
        def self.thread_proc(data : Void*) : Void*
          data
        end
      end

      def sample
        ->Thread.thread_proc(Void*)
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names
    analyzer.infer_types(result.identifier_symbols)

    result.diagnostics.should be_empty
    analyzer.type_inference_diagnostics.should be_empty
  end

  it "resolves bare enum members inside enum index syntax" do
    source = <<-CR
      @[Flags]
      enum CompileOptions
        None = 0
        IGNORE_CASE = 0x0000_0001
        MULTILINE = 0x0000_0006
        EXTENDED = 0x0000_0008
      end

      class Regex
        def options : CompileOptions
          CompileOptions::IGNORE_CASE
        end

        def inspect(io)
          if (options & ~CompileOptions[IGNORE_CASE, MULTILINE, EXTENDED]).none?
            io
          end
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names
    analyzer.infer_types(result.identifier_symbols)

    result.diagnostics.should be_empty
    analyzer.type_inference_diagnostics.should be_empty
  end

  it "resolves locals assigned in case branches after the case" do
    source = <<-CR
      def sample(justify, size, len)
        padding = (len - size)
        case justify
        when .< 0
          leftpadding, rightpadding = 0, padding
        when .> 0
          leftpadding, rightpadding = padding, 0
        else
          leftpadding = padding // 2
          rightpadding = padding - leftpadding
        end

        if leftpadding > 0
          rightpadding
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves inherited receiverless calls through implicit default superclasses" do
    source = <<-CR
      class Object
        def object_id
          1
        end
      end

      class Reference
      end

      struct Value
        def dup
          self
        end
      end

      struct Struct
      end

      class Example
        def sample
          object_id
        end
      end

      struct Point
        def sample
          dup
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves uppercase assignment constants inside class methods" do
    source = <<-CR
      class TaintAnalyzer
        FFI_METHODS = 1

        def ffi_methods
          FFI_METHODS
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves module-body macro-generated constants" do
    source = <<-CR
      module Crystal::MIR
        {% if true %}
          TARGET_POINTER_BYTES_U64 = 8_u64
        {% else %}
          TARGET_POINTER_BYTES_U64 = 4_u64
        {% end %}

        def self.pointer_bytes
          TARGET_POINTER_BYTES_U64
        end
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end

  it "resolves module-body macro-generated class var declarations with nilable path types" do
    source = <<-CR
      class Thread
      end

      lib LibC
        struct MachTimebaseInfo
        end
      end

      module Crystal::System::Thread
        {% if true %}
          @@current_thread : ::Thread?
          @@mach_timebase_info : LibC::MachTimebaseInfo?

          def self.current_thread?
            @@current_thread
          end
        {% end %}
      end
    CR

    parser = Frontend::Parser.new(Frontend::Lexer.new(source))
    program = parser.parse_program
    analyzer = Semantic::Analyzer.new(program)
    analyzer.collect_symbols
    result = analyzer.resolve_names

    result.diagnostics.should be_empty
  end
end
