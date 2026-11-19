require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def spec_replay_static_nilary_result(method : String, *, suspends : Bool) : Nil
    owner = "StaticNilaryResult"
    target = mangle_function_name("#{owner}.#{method}", [TypeRef::INT32])
    producer = "#{owner}.value"
    @module.has_function_with_body?(producer).should be_false
    remember_callsite_arg_types(target, [TypeRef::INT32])

    @force_lower_return_type_depth = 1
    @force_lower_retry_driver_active = true
    begin
      force_lower_function_for_return_type(target, bypass_inline_yield: true)
    ensure
      @force_lower_return_type_depth = 0
      @force_lower_retry_driver_active = false
    end

    request = @force_lower_retry_work.find do |work|
      work.is_a?(ForceLowerSuspendedRequest) && work.name == target
    end.as?(ForceLowerSuspendedRequest)
    if suspends
      request.should_not be_nil
      pending = request.not_nil!.pending
      pending.producer.should eq(producer)
      pending.producer_replay.should_not be_nil
      replay = pending.producer_replay.not_nil!
      replay.callsite.types.should be_empty
      replay.source_def.params.try(&.empty?).should_not be_false
      force_lower_replay_callsite_current?(producer, replay).should be_true
      run_force_lower_retry_driver(request.not_nil!).should be_true
    else
      request.should be_nil
    end

    settled_force_lower_result?(producer).should be_true
    settled_force_lower_result?(target).should be_true
    callee = @module.function_by_name(producer).not_nil!
    source_block_result_union_members(callee.return_type).not_nil!.to_set.should eq(Set{TypeRef::NIL, TypeRef::INT32})
    caller = @module.function_by_name(target).not_nil!
    caller.return_type.should eq(TypeRef::INT32)
    call = caller.blocks.flat_map(&.instructions).find do |instruction|
      instruction.is_a?(Call) && instruction.method_name == producer
    end
    call.should_not be_nil
    call.not_nil!.type.should eq(callee.return_type)
  end
end

private def static_nilary_result_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    lib StaticNilaryC
      fun getchar : Int32
    end

    struct StaticNilaryResult
      def self.bare(fallback : Int32) : Int32
        value = self.value
        value || fallback
      end

      def self.parenthesized(fallback : Int32) : Int32
        value = self.value()
        value || fallback
      end

      private def self.value
        code = StaticNilaryC.getchar
        code < 0 ? nil : code
      end

      def self.value(flag : Bool) : Bool
        flag
      end
    end
    CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::LibNode
      converter.register_lib(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  converter
end

describe "static nilary source result replay" do
  it "suspends the bare member call with its exact empty argument list" do
    static_nilary_result_converter.spec_replay_static_nilary_result("bare", suspends: true)
  end

  it "keeps empty parentheses as a control for the same private body" do
    static_nilary_result_converter.spec_replay_static_nilary_result("parenthesized", suspends: false)
  end
end
