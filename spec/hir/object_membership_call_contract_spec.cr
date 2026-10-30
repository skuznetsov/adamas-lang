require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"

private def lower_object_membership_contract(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena,
    sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << id.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  converter
end

private def object_membership_contract_source(invalid : Bool = false) : String
  source = <<-CRYSTAL
    class Object
      def in?(collection : Object) : Bool
        collection.includes?(self)
      end
    end
    abstract struct Value
    end
    abstract struct Struct
    end
    abstract struct Number
    end
    abstract struct Int
    end
    struct Char
    end
    struct Int32
    end
    class MembershipCharCollection < Object
      def includes?(value : Char) : Bool
        true
      end
    end
    class MembershipIntCollection < Object
      def includes?(value : Int32) : Bool
        true
      end
    end
    'a'.in?(MembershipCharCollection.new)
    7.in?(MembershipIntCollection.new)
  CRYSTAL
  source += "\n'a'.in?(MembershipIntCollection.new)\n" if invalid
  source
end

describe "inherited Object membership call contract" do
  it "retains the concrete value receiver and collection in each executable body" do
    converter = lower_object_membership_contract(object_membership_contract_source)
    main = converter.module.function_by_name("__adamas_main").not_nil!
    calls = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .select { |call| call.method_name.includes?("#in?") }
    calls.size.should eq(2)
    [{"Char", "MembershipCharCollection"}, {"Int32", "MembershipIntCollection"}].each do |owner, collection|
      call = calls.find { |candidate| candidate.method_name.starts_with?("#{owner}#in?$") }
      call.should_not be_nil
      function = converter.module.function_by_name(call.not_nil!.method_name).not_nil!
      converter.module.has_function_with_body?(function.name).should be_true
      function.params.size.should eq(2)
      function.params[0].type.should eq(owner == "Char" ? Adamas::HIR::TypeRef::CHAR : Adamas::HIR::TypeRef::INT32)
      function.params[1].type.should eq(converter.class_info[collection].type_ref)
      inner_calls = function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
        .select { |candidate| candidate.method_name.includes?("#includes?") }
      inner_calls.size.should eq(1)
      inner_calls.first.method_name.should start_with("#{collection}#includes?")
      inner_calls.first.virtual.should be_false
    end
    converter.module.has_function_with_body?("Object#in?$Object").should be_false
  end

  it "rejects an incompatible nested collection restriction" do
    expect_raises(Adamas::HIR::LoweringError, /includes/) do
      lower_object_membership_contract(object_membership_contract_source(invalid: true))
    end
  end

  it "retains a reference receiver forwarded to a selected collection body" do
    source = object_membership_contract_source + <<-CRYSTAL
      class Reference < Object
      end
      class MembershipToken < Reference
      end
      class MembershipReferenceCollection < Object
        def includes?(value : MembershipToken) : Bool
          true
        end
      end
      MembershipToken.new.in?(MembershipReferenceCollection.new)
    CRYSTAL
    converter = lower_object_membership_contract(source)
    main = converter.module.function_by_name("__adamas_main").not_nil!
    call = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .find { |candidate| candidate.method_name.starts_with?("MembershipToken#in?$") }
    call.should_not be_nil
    function = converter.module.function_by_name(call.not_nil!.method_name).not_nil!
    function.params.map(&.type).should eq([
      converter.class_info["MembershipToken"].type_ref,
      converter.class_info["MembershipReferenceCollection"].type_ref,
    ])
  end

  it "reuses bodies for repeated concrete operand contracts" do
    source = object_membership_contract_source
    24.times do
      source += "\n'b'.in?(MembershipCharCollection.new)\n8.in?(MembershipIntCollection.new)\n"
    end
    converter = lower_object_membership_contract(source)
    bodies = converter.module.functions.select do |function|
      function.name.includes?("#in?$") && converter.module.has_function_with_body?(function.name)
    end
    bodies.size.should eq(2)
  end

  it "preserves the same forwarding shape independently of the method name" do
    source = object_membership_contract_source
    source += <<-CRYSTAL
      class Reference < Object
      end
      class MembershipToken < Reference
      end
      class MembershipReferenceCollection < Object
        def includes?(value : MembershipToken) : Bool
          true
        end
      end
      MembershipToken.new.in?(MembershipReferenceCollection.new)
    CRYSTAL
    source = source.gsub("in?", "forwards_membership?")
    converter = lower_object_membership_contract(source)
    main = converter.module.function_by_name("__adamas_main").not_nil!
    call = main.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call))
      .find { |candidate| candidate.method_name.starts_with?("MembershipToken#forwards_membership?$") }
    call.should_not be_nil
    function = converter.module.function_by_name(call.not_nil!.method_name).not_nil!
    function.params.map(&.type).should eq([
      converter.class_info["MembershipToken"].type_ref,
      converter.class_info["MembershipReferenceCollection"].type_ref,
    ])
  end
end
