require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_queue_and_materialize_generic_anchor(name : String) : Adamas::HIR::TypeRef
    old_defer = @defer_monomorphization
    old_eager = @eager_monomorphization
    begin
      @defer_monomorphization = true
      type_ref = type_ref_for_name(name)
      @eager_monomorphization = true
      flush_pending_monomorphizations
      type_ref
    ensure
      @defer_monomorphization = old_defer
      @eager_monomorphization = old_eager
    end
  end

  def __test_generic_anchor_type_ref(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  def __test_generic_anchor_receiver_map(type_ref : Adamas::HIR::TypeRef) : Hash(String, String)
    type_param_map_for_receiver_type(type_ref)
  end

  def __test_lower_generic_anchor_method(name : String) : Nil
    lower_function_if_needed(name)
  end
end

private def generic_monomorphization_anchor_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class Child
    end

    class Box(T)
      module Child
      end

      @value : T

      def value : T
        @value
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty

  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.no_prelude = true
  converter.arena = arena
  converter.seed_top_level_type_names(["Child", "Box"])
  converter.seed_top_level_class_kinds([{"Child", false}, {"Box", false}])

  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
  end
  converter
end

describe "generic monomorphization root anchors" do
  it "keeps root Child bound through queued Box specialization and concrete receiver maps" do
    converter = generic_monomorphization_anchor_converter
    box_type = converter.__test_queue_and_materialize_generic_anchor("Box(::Child)")
    box_type.should_not eq(Adamas::HIR::TypeRef::VOID)

    box_descriptor = converter.module.get_type_descriptor(box_type).not_nil!
    box_descriptor.name.should eq("Box(Child)")
    root_child = converter.__test_generic_anchor_type_ref("::Child")
    nested_child = converter.__test_generic_anchor_type_ref("Box::Child")
    root_child.should_not eq(Adamas::HIR::TypeRef::VOID)
    nested_child.should_not eq(Adamas::HIR::TypeRef::VOID)
    root_child.should_not eq(nested_child)

    receiver_map = converter.__test_generic_anchor_receiver_map(box_type)
    receiver_map["T"].should eq("::Child")

    box_info = converter.class_info[box_descriptor.name]
    value_ivar = box_info.ivars.find { |ivar| ivar.name == "@value" }.not_nil!
    value_ivar.type.should eq(root_child)
    value_ivar.type.should_not eq(nested_child)

    converter.__test_lower_generic_anchor_method("#{box_descriptor.name}#value")
    value_method = converter.module.function_by_name("#{box_descriptor.name}#value")
    value_method.should_not be_nil
    value_method.not_nil!.return_type.should eq(root_child)
  end
end
