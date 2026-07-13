require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

# Narrow test-only seams keep the contract assertions at HIR level without
# making the production lowering helpers public.
class Adamas::HIR::AstToHir
  def __test_receiver_type_name(name : String) : String
    get_type_name_from_ref(type_ref_for_name(name))
  end

  def __test_type_name_for_ref(type_ref : TypeRef) : String
    get_type_name_from_ref(type_ref)
  end

  def __test_receiver_param_coerce_types(
    receiver_name : String,
    method_name : String,
    argument_type_names : Array(String),
  ) : Array(String)
    receiver_type = type_ref_for_name(receiver_name)
    function = @module.create_function("__receiver_param_contract_probe", TypeRef::VOID)
    context = LoweringContext.new(function, @module, @arena)
    arguments = argument_type_names.map_with_index do |name, index|
      parameter = function.add_param("arg#{index}", type_ref_for_name(name))
      context.register_type(parameter.id, parameter.type)
      parameter.id
    end
    result = coerce_args_to_receiver_param_types(context, receiver_type, method_name, arguments)
    result[1].map { |type| get_type_name_from_ref(type) }
  end

  def __test_receiver_param_coerce_instruction_count(
    receiver_name : String,
    method_name : String,
    argument_type_names : Array(String),
  ) : Int32
    receiver_type = type_ref_for_name(receiver_name)
    function = @module.create_function("__receiver_param_instruction_probe", TypeRef::VOID)
    context = LoweringContext.new(function, @module, @arena)
    arguments = argument_type_names.map_with_index do |name, index|
      parameter = function.add_param("arg#{index}", type_ref_for_name(name))
      context.register_type(parameter.id, parameter.type)
      parameter.id
    end
    coerce_args_to_receiver_param_types(context, receiver_type, method_name, arguments)
    function.blocks.sum { |block| block.instructions.size }.to_i32
  end

  def __test_nil_union_equality_emits_union_is : Bool
    union_type = create_union_type_for_nullable(TypeRef::INT32)
    function = @module.create_function("__nil_union_equality_probe", TypeRef::BOOL)
    context = LoweringContext.new(function, @module, @arena)
    union_value = function.add_param("union_value", union_type)
    nil_value = function.add_param("nil_value", TypeRef::NIL)
    context.register_type(union_value.id, union_type)
    context.register_type(nil_value.id, TypeRef::NIL)
    lower_value_equality_intrinsic(context, union_value.id, nil_value.id)
    function.blocks.flat_map(&.instructions).any? { |instruction| instruction.is_a?(UnionIs) }
  end

  def __test_nil_union_equality_union_type : TypeRef
    union_type = create_union_type_for_nullable(TypeRef::INT32)
    function = @module.create_function("__nil_union_equality_type_probe", TypeRef::BOOL)
    context = LoweringContext.new(function, @module, @arena)
    union_value = function.add_param("union_value", union_type)
    nil_value = function.add_param("nil_value", TypeRef::NIL)
    context.register_type(union_value.id, union_type)
    context.register_type(nil_value.id, TypeRef::NIL)
    lower_value_equality_intrinsic(context, union_value.id, nil_value.id)
    instruction = function.blocks.flat_map(&.instructions).find { |value| value.is_a?(UnionIs) }
    instruction ? instruction.as(UnionIs).union_type : TypeRef::VOID
  end

  def __test_hir_element_byte_size(type_name : String) : Int32
    hir_element_byte_size(type_ref_for_name(type_name))
  end

  def __test_union_sidecar_size_after_legacy_hash_delete(type_name : String) : {Int32, Int32}
    type_ref = type_ref_for_name(type_name)
    descriptor = union_descriptor_from_sidecar(type_ref)
    raise "missing authoritative union sidecar for #{type_name}" unless descriptor
    @union_descriptors.delete(hir_to_mir_type_ref(type_ref))
    {descriptor.total_size, hir_element_byte_size(type_ref)}
  end

  def __test_hir_element_byte_size_without_union_descriptor(type_name : String) : Int32
    type_ref = type_ref_for_name(type_name)
    mir_type_ref = hir_to_mir_type_ref(type_ref)
    @union_descriptors.delete(mir_type_ref)
    @union_descriptor_entries.reject! { |entry| entry.type_ref == mir_type_ref }
    hir_element_byte_size(type_ref)
  end
end

private alias ReceiverMonomorphization = {String, Array(String), String}

private def lower_receiver_source_hir(
  code : String,
  monomorphizations = [] of ReceiverMonomorphization,
) : {Adamas::HIR::AstToHir, Array(Adamas::HIR::Function)}
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code)
  )
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  defs = [] of Adamas::Compiler::Frontend::DefNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  result.roots.each do |root_id|
    node = result.arena[root_id]
    case node
    when Adamas::Compiler::Frontend::DefNode
      defs << node
    when Adamas::Compiler::Frontend::ClassNode
      classes << node
    end
  end
  classes.each { |node| converter.register_class(node) }
  if classes.any? { |node| String.new(node.name) == "Generic" }
    converter.__test_monomorphize_receiver_contract("Generic", ["String", "Int32?"], "Generic(String, Int32?)")
  end
  monomorphizations.each do |base_name, type_args, specialized_name|
    converter.__test_monomorphize_receiver_contract(base_name, type_args, specialized_name)
  end
  defs.each { |node| converter.register_function(node) }
  functions = defs.map { |node| converter.lower_def(node) }
  {converter, functions}
end

private def receiver_param_contract_converter : Adamas::HIR::AstToHir
  source = <<-CRYSTAL
    class String
    end

    class Box(K, V)
      def []=(key : K, value : V) : V
        value
      end

      def has_key?(key)
        false
      end
    end

    class Generic(A, B)
      def []=(key : A, value : B) : B
        value
      end
    end

    class Wrapper(A)
      def []=(key : K, value : K) : K
        value
      end
    end

    class Overloaded(K, V)
      def []=(key : K, value : V) : V
        value
      end

      def []=(key : String, value : Int32) : Int32
        value
      end
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source)
  )
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena
  result.roots.each do |root_id|
    node = result.arena[root_id]
    converter.register_class(node) if node.is_a?(Adamas::Compiler::Frontend::ClassNode)
  end
  converter.__test_monomorphize_receiver_contract(
    "Box",
    ["Tuple(String, String, Int32?, Bool)", "Int32?"],
    "Box(Tuple(String, String, Int32?, Bool), Int32?)",
  )
  converter.__test_monomorphize_receiver_contract("Box", ["Float64", "Int32"], "Box(Float64, Int32)")
  converter.__test_monomorphize_receiver_contract("Box", ["Int32", "Int32"], "Box(Int32, Int32)")
  converter.__test_monomorphize_receiver_contract("Generic", ["String", "Int32?"], "Generic(String, Int32?)")
  converter.__test_monomorphize_receiver_contract("Wrapper", ["String"], "Wrapper(String)")
  converter.__test_monomorphize_receiver_contract("Overloaded", ["String", "Int32?"], "Overloaded(String, Int32?)")
  converter
end

class Adamas::HIR::AstToHir
  def __test_monomorphize_receiver_contract(
    base_name : String,
    type_args : Array(String),
    specialized_name : String,
  ) : Nil
    monomorphize_generic_class(base_name, type_args, specialized_name)
  end
end

describe "receiver-generic argument coercion" do
  it "widens tuple and value arguments before the mangle boundary" do
    converter = receiver_param_contract_converter
    owner = "Box(Tuple(String, String, Int32?, Bool), Int32?)"
    converter.__test_receiver_type_name(owner).should eq(owner)
    converter.__test_receiver_param_coerce_types(
      owner,
      "#{owner}#[]=",
      ["Tuple(String, String, Int32, Bool)", "Int32"],
    ).should eq(["Tuple(String, String, Nil | Int32, Bool)", "Nil | Int32"])
  end

  it "leaves untyped lookup methods call-site-specialized" do
    converter = receiver_param_contract_converter
    owner = "Box(Tuple(String, String, Int32?, Bool), Int32?)"
    narrow = "Tuple(String, String, Int32, Bool)"
    converter.__test_receiver_param_coerce_types(owner, "#{owner}#has_key?", [narrow]).should eq([narrow])
  end

  it "does not allocate or cast an already exact scalar contract" do
    converter = receiver_param_contract_converter
    owner = "Box(Int32, Int32)"
    converter.__test_receiver_param_coerce_types(owner, "#{owner}#[]=", ["Int32", "Int32"]).should eq(["Int32", "Int32"])
  end

  it "does not introduce numeric casts or pointer-to-scalar coercions" do
    converter = receiver_param_contract_converter

    float_owner = "Box(Float64, Int32)"
    float_args = ["Int32", "Int32"]
    converter.__test_receiver_param_coerce_types(float_owner, "#{float_owner}#[]=", float_args).should eq(float_args)
    converter.__test_receiver_param_coerce_instruction_count(float_owner, "#{float_owner}#[]=", float_args).should eq(0)

    scalar_owner = "Box(Int32, Int32)"
    pointer_args = ["Pointer", "Int32"]
    converter.__test_receiver_param_coerce_types(scalar_owner, "#{scalar_owner}#[]=", pointer_args).should eq(pointer_args)
    converter.__test_receiver_param_coerce_instruction_count(scalar_owner, "#{scalar_owner}#[]=", pointer_args).should eq(0)
  end

  it "binds only the generic template names declared by a custom setter" do
    converter = receiver_param_contract_converter
    owner = "Generic(String, Int32?)"
    converter.__test_receiver_param_coerce_types(
      owner,
      "#{owner}#[]=",
      ["String", "Int32"],
    ).should eq(["String", "Nil | Int32"])
  end

  it "does not treat K as an alias for a Wrapper(A) annotation" do
    converter = receiver_param_contract_converter
    owner = "Wrapper(String)"
    before = ["Int32", "Int32"]
    converter.__test_receiver_param_coerce_types(owner, "#{owner}#[]=", before).should eq(before)
  end

  it "fails closed on overloaded setters without emitting coercion garbage" do
    converter = receiver_param_contract_converter
    owner = "Overloaded(String, Int32?)"
    before = ["String", "Int32"]
    converter.__test_receiver_param_coerce_types(owner, "#{owner}#[]=", before).should eq(before)
    converter.__test_receiver_param_coerce_instruction_count(owner, "#{owner}#[]=", before).should eq(0)
  end

  it "recognizes nullable union equality against a concrete nil" do
    converter = receiver_param_contract_converter
    converter.__test_nil_union_equality_emits_union_is.should be_true
    converter.__test_type_name_for_ref(converter.__test_nil_union_equality_union_type).should eq("Nil | Int32")
  end
end

describe "receiver tuple union slot sizing" do
  it "matches authoritative tagged and raw nullable union storage" do
    converter = receiver_param_contract_converter
    converter.__test_hir_element_byte_size("Nil | Int32").should eq(12)
    converter.__test_hir_element_byte_size("Nil | Int64").should eq(16)
    converter.__test_hir_element_byte_size("Nil | String").should eq(8)
    converter.__test_hir_element_byte_size("Nil | Pointer(Int32)").should eq(8)
    converter.__test_hir_element_byte_size("Nil | Pointer(Int32) | String").should eq(16)
    converter.__test_hir_element_byte_size("Nil | Pointer(Int32) | Pointer(Int64)").should eq(16)
  end

  it "keeps the append-only sidecar authoritative when the legacy hash entry disappears" do
    converter = receiver_param_contract_converter
    expected, actual = converter.__test_union_sidecar_size_after_legacy_hash_delete(
      "Nil | Tuple(Int64, Int64)"
    )
    expected.should be > 8
    actual.should eq(expected)
  end

  it "uses the HIR textual fallback for one nullable raw pointer only" do
    converter = receiver_param_contract_converter
    converter.__test_hir_element_byte_size_without_union_descriptor(
      "Nil | Pointer(Int32)"
    ).should eq(8)
    converter.__test_hir_element_byte_size_without_union_descriptor(
      "Nil | Pointer(Int32) | String"
    ).should eq(16)
    converter.__test_hir_element_byte_size_without_union_descriptor(
      "Nil | Pointer(Int32) | Pointer(Int64)"
    ).should eq(16)
    converter.__test_hir_element_byte_size_without_union_descriptor(
      "Nil | Tuple(Int64, Int64)"
    ).should eq(24)
  end
end

describe "nullable tuple and hash equality HIR" do
  it "emits typed UnionIs for tuple nullable element equality in both orders" do
    converter, functions = lower_receiver_source_hir(<<-CRYSTAL)
      def tuple_eq(value : {Int32?, Int32}) : Bool
        value[0] == nil
      end

      def tuple_ne(value : {Int32?, Int32}) : Bool
        nil != value[0]
      end
    CRYSTAL

    functions.each do |function|
      checks = function.blocks.flat_map(&.instructions).select(Adamas::HIR::UnionIs)
      checks.should_not be_empty
      checks.each do |check|
        check.union_type.should_not eq(Adamas::HIR::TypeRef::VOID)
        converter.__test_type_name_for_ref(check.union_type).should eq("Nil | Int32")
      end
    end
  end

  it "emits typed UnionIs for a nil comparison from Hash#[]?" do
    converter, functions = lower_receiver_source_hir(<<-CRYSTAL)
      def hash_nil(value : Hash(String, Int32?)) : Bool
        value["missing"]? == nil
      end
    CRYSTAL

    function = functions.first
    checks = function.blocks.flat_map(&.instructions).select(Adamas::HIR::UnionIs)
    checks.should_not be_empty
    checks.each do |check|
      check.union_type.should_not eq(Adamas::HIR::TypeRef::VOID)
      converter.__test_type_name_for_ref(check.union_type).should eq("Nil | Int32")
    end
  end
end

describe "index-setter source route" do
  it "passes receiver-widened arguments into the resolved setter call" do
    _converter, functions = lower_receiver_source_hir(<<-CRYSTAL)
      class Generic(A, B)
        def []=(key : A, value : B) : B
          value
        end
      end

      def assign(box : Generic(String, Int32?)) : Int32
        box["key"] = 1
        1
      end
    CRYSTAL

    function = functions.find { |candidate| candidate.name.starts_with?("assign$") }
    function.should_not be_nil
    calls = function.not_nil!.blocks.flat_map(&.instructions).select(Adamas::HIR::Call)
    setter = calls.find { |call| call.method_name.includes?("#[]=") }
    setter.should_not be_nil
    setter.not_nil!.method_name.should contain("Nil | Int32")
    wrapped_arg = setter.not_nil!.args.last
    wrapped = function.not_nil!.blocks.flat_map(&.instructions).find { |instruction| instruction.id == wrapped_arg }
    wrapped.should be_a(Adamas::HIR::UnionWrap)
    _converter.__test_type_name_for_ref(wrapped.not_nil!.type).should eq("Nil | Int32")
  end

  it "reads tuple elements at authoritative nullable-union offsets before widening" do
    converter, functions = lower_receiver_source_hir(
      <<-CRYSTAL,
        class Generic(A, B)
          def []=(key : A, value : B) : B
            value
          end
        end

        def assign_tuple(
          box : Generic({Int32?, Int32?}, Int32?),
          key : {Int32?, Int32}
        ) : Int32
          box[key] = 1
          1
        end
      CRYSTAL
      [{
        "Generic",
        ["Tuple(Int32?, Int32?)", "Int32?"],
        "Generic(Tuple(Int32?, Int32?), Int32?)",
      }],
    )
    function = functions.find { |candidate| candidate.name.starts_with?("assign_tuple$") }
    function.should_not be_nil
    field_gets = function.not_nil!.blocks.flat_map(&.instructions).select(Adamas::HIR::FieldGet)
    tuple_reads = field_gets.select { |field_get| field_get.field_name.starts_with?("@__") }
    tuple_reads.map(&.field_offset).should eq([0, 12])
    tuple_reads.map { |field_get| converter.__test_type_name_for_ref(field_get.type) }
      .should eq(["Nil | Int32", "Int32"])
  end
end

describe "hash-literal receiver contract" do
  it "resolves a typed nonempty literal to the widened setter ABI" do
    converter, functions = lower_receiver_source_hir(
      <<-CRYSTAL,
        class Hash(K, V)
          def []=(key : K, value : V) : V
            value
          end
        end

        def build_hash : Int32
          table = { {1, 7} => 42 } of {Int32?, Int32?} => Int32?
          1
        end
      CRYSTAL
      [{
        "Hash",
        ["Tuple(Int32?, Int32?)", "Int32?"],
        "Hash(Tuple(Int32?, Int32?), Int32?)",
      }],
    )

    function = functions.find { |candidate| candidate.name.starts_with?("build_hash") }
    function.should_not be_nil
    instructions = function.not_nil!.blocks.flat_map(&.instructions)
    setter = instructions.select(Adamas::HIR::Call).find { |call| call.method_name.includes?("#[]=") }
    setter.should_not be_nil
    setter.not_nil!.method_name.should eq(
      "Hash(Tuple(Int32?, Int32?), Int32?)#[]=$Tuple(Nil | Int32, Nil | Int32)_Nil | Int32"
    )

    key_arg = instructions.find { |instruction| instruction.id == setter.not_nil!.args[0] }
    key_arg.should be_a(Adamas::HIR::Allocate)
    converter.__test_type_name_for_ref(key_arg.not_nil!.type)
      .should eq("Tuple(Nil | Int32, Nil | Int32)")
    key_elements = key_arg.as(Adamas::HIR::Allocate).constructor_args
    key_elements.size.should eq(2)
    key_elements.each do |element_id|
      instructions.find { |instruction| instruction.id == element_id }.should be_a(Adamas::HIR::UnionWrap)
    end

    value_arg = instructions.find { |instruction| instruction.id == setter.not_nil!.args[1] }
    value_arg.should be_a(Adamas::HIR::UnionWrap)
    converter.__test_type_name_for_ref(value_arg.not_nil!.type).should eq("Nil | Int32")
  end
end
