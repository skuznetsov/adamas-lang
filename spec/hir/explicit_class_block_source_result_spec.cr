require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  # Infer the actual caller expression from a fresh declaration-only converter.
  # This intentionally probes infer_type_from_expr rather than calling the
  # selected-class return helper directly.
  def __test_explicit_class_block_source_result(
    owner_name : String,
    caller_method : String,
  ) : String?
    caller_name = "#{owner_name}.#{caller_method}"
    caller_defs = @function_defs.select do |name, _|
      name == caller_name || name.starts_with?("#{caller_name}$")
    end.values.uniq(&.object_id)
    raise "expected one registered caller #{caller_name}, got #{caller_defs.size}" unless caller_defs.size == 1

    caller_def = caller_defs.first
    caller_arena = registered_arena_for_def(caller_def) ||
                   raise "caller #{caller_name} has no registered source arena"
    body = caller_def.body || raise "caller #{caller_name} has no body"
    call_expr = body.last? || raise "caller #{caller_name} has an empty body"
    raise "caller #{caller_name} tail must be a CallNode" unless caller_arena[call_expr].is_a?(Adamas::Compiler::Frontend::CallNode)

    old_arena = @arena
    old_current_class = @current_class
    old_current_method = @current_method
    old_current_def = @current_def_node
    old_current_method_is_class = @current_method_is_class
    old_infer_self_type_name = @infer_self_type_name
    old_infer_body_context = @infer_body_context
    old_typeof_locals = @current_typeof_locals
    old_typeof_names = @current_typeof_local_names

    begin
      @arena = caller_arena
      @current_class = owner_name
      @current_method = caller_method
      @current_def_node = caller_def
      @current_method_is_class = true
      @infer_self_type_name = owner_name
      @infer_body_context = body
      @current_typeof_locals = {} of String => Adamas::HIR::TypeRef
      @current_typeof_local_names = {} of String => String

      infer_type_from_expr(call_expr, owner_name).try do |type_ref|
        get_type_name_from_ref(type_ref)
      end
    ensure
      @arena = old_arena
      @current_class = old_current_class
      @current_method = old_current_method
      @current_def_node = old_current_def
      @current_method_is_class = old_current_method_is_class
      @infer_self_type_name = old_infer_self_type_name
      @infer_body_context = old_infer_body_context
      @current_typeof_locals = old_typeof_locals
      @current_typeof_local_names = old_typeof_names
    end
  end
end

private def parse_explicit_class_block_source_result(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  parsed = parser.parse_program
  raise parser.diagnostics.inspect unless parser.diagnostics.empty?

  converter = Adamas::HIR::AstToHir.new(
    parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source},
  )
  converter.arena = parsed.arena
  parsed.roots.each do |root_id|
    if node = parsed.arena[root_id].as?(Adamas::Compiler::Frontend::ClassNode)
      converter.register_class(node)
    end
  end
  converter
end

private def explicit_class_block_source_result_source : String
  <<-CRYSTAL
    struct ExplicitClassBlockOwnerBox(T)
      def initialize(@value : T)
      end

      def value : T
        @value
      end

      def self.build(&block : -> T) : ExplicitClassBlockOwnerBox(T)
        ExplicitClassBlockOwnerBox(T).new(yield)
      end

      def self.shadow(value : T, &block : -> T) : ExplicitClassBlockOwnerBox(T) forall T
        ExplicitClassBlockOwnerBox(T).new(yield)
      end

      # A same-name instance method must not answer a class-receiver call.
      def build(&block : -> String) : String
        yield
      end
    end

    struct ExplicitClassBlockWrappedOwnerBox(T)
      def initialize(@value : T)
      end

      begin
        def self.build(&block : -> T) : ExplicitClassBlockWrappedOwnerBox(T)
          ExplicitClassBlockWrappedOwnerBox(T).new(yield)
        end
      end
    end

    class ExplicitSelfBlockProbe
      def self.build(&block : -> Int32) : ExplicitClassBlockOwnerBox(Int32)
        ExplicitClassBlockOwnerBox(Int32).new(yield)
      end

      # This instance overload has a deliberately different result.
      def build(&block : -> String) : String
        yield
      end

      def self.self_receiver_caller
        self.build { 68_i32 }
      end
    end

    class ExplicitClassBlockSourceProbe
      def self.bare_owner_caller
        ExplicitClassBlockOwnerBox.build { 65_i32 }
      end

      def self.explicit_owner_caller
        ExplicitClassBlockOwnerBox(Int32).build { 66_i32 }
      end

      def self.method_forall_shadows_owner_caller
        ExplicitClassBlockOwnerBox(String).shadow(0_i32) { 67_i32 }
      end

      def self.wrapped_bare_owner_caller
        ExplicitClassBlockWrappedOwnerBox.build { 69_i32 }
      end
    end
  CRYSTAL
end

describe "explicit class block source result inference with a fresh converter" do
  it "binds an uninstantiated generic owner from the callback result" do
    converter = parse_explicit_class_block_source_result(explicit_class_block_source_result_source)
    converter.__test_explicit_class_block_source_result(
      "ExplicitClassBlockSourceProbe", "bare_owner_caller",
    ).should eq("ExplicitClassBlockOwnerBox(Int32)")
  end

  it "preserves the concrete generic owner for an explicit class receiver" do
    converter = parse_explicit_class_block_source_result(explicit_class_block_source_result_source)
    converter.__test_explicit_class_block_source_result(
      "ExplicitClassBlockSourceProbe", "explicit_owner_caller",
    ).should eq("ExplicitClassBlockOwnerBox(Int32)")
  end

  it "lets method forall T shadow the receiver owner's T" do
    converter = parse_explicit_class_block_source_result(explicit_class_block_source_result_source)
    converter.__test_explicit_class_block_source_result(
      "ExplicitClassBlockSourceProbe", "method_forall_shadows_owner_caller",
    ).should eq("ExplicitClassBlockOwnerBox(Int32)")
  end

  it "registers a bare generic class helper inside a handler-free begin wrapper" do
    converter = parse_explicit_class_block_source_result(explicit_class_block_source_result_source)
    converter.__test_explicit_class_block_source_result(
      "ExplicitClassBlockSourceProbe", "wrapped_bare_owner_caller",
    ).should eq("ExplicitClassBlockWrappedOwnerBox(Int32)")
  end

  it "keeps an explicit self class receiver on the class method despite a same-name instance method" do
    converter = parse_explicit_class_block_source_result(explicit_class_block_source_result_source)
    converter.__test_explicit_class_block_source_result(
      "ExplicitSelfBlockProbe", "self_receiver_caller",
    ).should eq("ExplicitClassBlockOwnerBox(Int32)")
  end
end
