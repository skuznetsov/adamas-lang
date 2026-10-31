require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  # Keep this spec independent of deferred_constant_self_kind_spec load order.
  def __test_deferred_proc_literal_lazy_mode=(lazy : Bool) : Bool
    @lazy_classvar_init_active = lazy
  end

  def __test_deferred_proc_literal_entries : Array({String, Bool, Bool, String?})
    @deferred_constant_inits.map do |entry|
      full_name = deferred_constant_full_name(entry.owner, entry.name)
      type_name = @constant_types[full_name]?.try { |type| generic_param_type_name_from_ref(type) }
      value_node = entry.arena[entry.value_id]
      {full_name, entry.value_id.invalid?, value_node.is_a?(Adamas::Compiler::Frontend::ProcLiteralNode), type_name}
    end
  end

  def __test_deferred_proc_literal_writes : Array({String, String, String, String?})
    main = @module.function_by_name("__adamas_main").not_nil!
    instructions = main.blocks.flat_map(&.instructions)
    instructions.compact_map do |instruction|
      next unless write = instruction.as?(ClassVarSet)
      next unless write.class_name.starts_with?("DeferredProcLiteral")

      value = instructions.find { |candidate| candidate.id == write.value }
      make_proc = value.try(&.as?(MakeProc))
      func_pointer = if proc_value = make_proc
                       instructions.find { |candidate| candidate.id == proc_value.fn_ptr }.try(&.as?(FuncPointer))
                     end
      {write.class_name, write.var_name, generic_param_type_name_from_ref(write.type), func_pointer.try(&.func_name)}
    end
  end

  def __test_type_name(type : TypeRef) : String
    get_type_name_from_ref(type)
  end

  def __test_deferred_proc_literal_type(name : String) : String?
    @constant_types[name]?.try { |type| generic_param_type_name_from_ref(type) }
  end
end

private def register_deferred_proc_literal_constants(
  source : String,
  lazy : Bool,
) : {Adamas::HIR::AstToHir, Array(UInt64)}
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter.__test_deferred_proc_literal_lazy_mode = lazy

  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  main = [] of UInt64
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    else
      main << root_id.index.to_u64
    end
  end

  modules.each { |node| converter.lower_module(node) }
  {converter, main}
end

describe "deferred Proc literal constants" do
  [true, false].each do |lazy|
    it "retains Proc signatures and emits distinct initializers (lazy=#{lazy})" do
      converter, main = register_deferred_proc_literal_constants(<<-CRYSTAL, lazy)
        struct Proc
          @[Primitive(:proc_call)]
          def call(*args : *T) : R
          end
        end

        module DeferredProcLiteralOwner
          NOARG = -> { 65 }
          TYPED = ->(value : Int32) { value }
        end

        module DeferredProcLiteralForeign
          NOARG = -> { 66 }
        end
        CRYSTAL

      entries = converter.__test_deferred_proc_literal_entries
      entries.map(&.[0]).sort.should eq([
        "DeferredProcLiteralForeign::NOARG",
        "DeferredProcLiteralOwner::NOARG",
        "DeferredProcLiteralOwner::TYPED",
      ])
      entries.each do |(_, invalid, proc_literal, _)|
        invalid.should be_false
        proc_literal.should be_true
      end

      converter.lower_main(main)
      converter.flush_pending_functions

      entries.to_h { |(name, _, _, _)| {name, converter.__test_deferred_proc_literal_type(name)} }.should eq({
        "DeferredProcLiteralForeign::NOARG" => "Proc(Int32)",
        "DeferredProcLiteralOwner::NOARG" => "Proc(Int32)",
        "DeferredProcLiteralOwner::TYPED" => "Proc(Int32, Int32)",
      })

      writes = converter.__test_deferred_proc_literal_writes
      writes.size.should eq(3)
      writes.map { |(owner, name, _, _)| "#{owner}::#{name}" }.sort.should eq([
        "DeferredProcLiteralForeign::NOARG",
        "DeferredProcLiteralOwner::NOARG",
        "DeferredProcLiteralOwner::TYPED",
      ])
      writes.each { |write| write[3].should_not be_nil }
      writes.map { |write| write[3].not_nil! }.uniq.size.should eq(3)
      converter.module.functions.count(&.name.starts_with?("__crystal_proc_")).should eq(3)
      writes.map(&.[2]).sort.should eq([
        "Proc(Int32)",
        "Proc(Int32)",
        "Proc(Int32, Int32)",
      ])

      writes.each do |(_, name, _, body_name)|
        proc_body = converter.module.function_by_name(body_name.not_nil!).not_nil!
        if name == "NOARG"
          proc_body.params.should be_empty
        else
          proc_body.params.map { |param| converter.__test_type_name(param.type) }.should eq(["Int32"])
        end
        converter.__test_type_name(proc_body.return_type).should eq("Int32")
      end
    end
  end
end
