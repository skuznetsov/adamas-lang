require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_generic_owner_materialization_context(
    base_name : String,
    type_args : Array(String),
    specialized_name : String,
    caller_owner : String?,
    caller_method : String?,
    caller_class_method : Bool,
    eager : Bool,
  ) : Tuple(String?, String?, Bool)
    saved_owner = @current_class
    saved_method = @current_method
    saved_class_method = @current_method_is_class
    saved_eager = @eager_monomorphization
    begin
      @current_class = caller_owner
      @current_method = caller_method
      @current_method_is_class = caller_class_method
      @eager_monomorphization = eager
      monomorphize_generic_class(base_name, type_args, specialized_name)
      {@current_class, @current_method, @current_method_is_class}
    ensure
      @current_class = saved_owner
      @current_method = saved_method
      @current_method_is_class = saved_class_method
      @eager_monomorphization = saved_eager
    end
  end
end

private def eager_generic_owner_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class EagerOwnerBox(T)
      def initialize(@value : T)
      end

      def value : T
        @value
      end
    end

    class EagerOwnerHolder(T)
      def initialize(value : T)
        @local = EagerOwnerBox(T).new(value)
        @relative = EagerOwnerBox(T).new(value)
        @rooted = EagerOwnerBox(T).new(value)
      end
    end
  CRYSTAL
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
  converter.seed_top_level_type_names(["EagerOwnerBox", "EagerOwnerHolder"])
  converter.seed_top_level_class_kinds([
    {"EagerOwnerBox", false}, {"EagerOwnerHolder", false},
  ])
  program.roots.each do |id|
    converter.register_class(arena[id].as(Adamas::Compiler::Frontend::ClassNode))
  end
  converter
end

private def materialize_eager_owner_box(
  converter : Adamas::HIR::AstToHir,
  class_method : Bool = false,
  eager : Bool = true,
) : Tuple(String?, String?, Bool)
  converter.__test_generic_owner_materialization_context(
    "EagerOwnerBox", ["Int32"], "EagerOwnerBox(Int32)",
    "EagerOwnerHolder(Int32)", "initialize", class_method, eager,
  )
end

private def materialize_eager_owner_holder(converter : Adamas::HIR::AstToHir) : Nil
  converter.__test_generic_owner_materialization_context(
    "EagerOwnerHolder", ["Int32"], "EagerOwnerHolder(Int32)",
    nil, nil, false, true,
  )
end

private def expect_disjoint_eager_owner_layouts(converter : Adamas::HIR::AstToHir) : Nil
  converter.class_info["EagerOwnerBox(Int32)"].ivars.map(&.name).sort.should eq(["@value"])
  converter.class_info["EagerOwnerHolder(Int32)"].ivars.map(&.name).sort.should eq([
    "@local", "@relative", "@rooted",
  ])
end

describe "eager generic owner restoration" do
  it "restores the active instance-method owner after a cold specialization" do
    converter = eager_generic_owner_converter
    materialize_eager_owner_box(converter).should eq({
      "EagerOwnerHolder(Int32)", "initialize", false,
    })
  end

  it "preserves the caller method and class-method flag during eager lowering" do
    converter = eager_generic_owner_converter
    materialize_eager_owner_box(converter, class_method: true).should eq({
      "EagerOwnerHolder(Int32)", "initialize", true,
    })
  end

  it "keeps the ordinary lazy materialization context unchanged" do
    converter = eager_generic_owner_converter
    materialize_eager_owner_box(converter, eager: false).should eq({
      "EagerOwnerHolder(Int32)", "initialize", false,
    })
  end

  it "keeps an already materialized eager receiver from changing its caller" do
    converter = eager_generic_owner_converter
    materialize_eager_owner_box(converter)
    materialize_eager_owner_box(converter, class_method: true).should eq({
      "EagerOwnerHolder(Int32)", "initialize", true,
    })
  end

  it "does not publish caller fields into a cold nested eager specialization" do
    converter = eager_generic_owner_converter
    materialize_eager_owner_holder(converter)
    expect_disjoint_eager_owner_layouts(converter)
  end

  it "keeps the same separate layouts when the nested specialization is already warm" do
    converter = eager_generic_owner_converter
    materialize_eager_owner_box(converter)
    materialize_eager_owner_holder(converter)
    expect_disjoint_eager_owner_layouts(converter)
  end
end
