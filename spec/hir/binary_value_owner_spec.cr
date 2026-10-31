require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_drain_binary_owner_bodies : Nil
    process_pending_lower_functions
  end

  def __test_binary_owner_alias_resolution(
    signature_base_name : String,
    runtime_owner : String,
    forged_alias : String,
    wrong_owner_alias : String,
    wrong_signature_base_name : String,
  )
    source_name = function_def_overloads(signature_base_name).find do |candidate_name|
      candidate = @function_defs[candidate_name]?
      !candidate.nil? && !registered_arena_for_def(candidate.not_nil!).nil?
    end || raise "missing registered source def for #{signature_base_name}"
    source_def = @function_defs[source_name].not_nil!
    source_arena = registered_arena_for_def(source_def) || raise "missing source arena for #{source_name}"
    canonical_name = registered_name_for_logical_def(signature_base_name, source_def) ||
                     raise "missing canonical source name for #{signature_base_name}"

    # Model a generated runtime alias that points at the exact source Def and
    # arena. It must not replace the lexical owner selected from the signature.
    @function_defs[forged_alias] = source_def
    @function_def_arenas[forged_alias] = source_arena
    @function_defs[wrong_owner_alias] = source_def
    @function_def_arenas[wrong_owner_alias] = source_arena

    {
      canonical_name: canonical_name,
      preferred_name: registered_name_for_logical_def(signature_base_name, source_def, forged_alias),
      wrong_owner_preferred_name: registered_name_for_logical_def(
        wrong_signature_base_name,
        source_def,
        wrong_owner_alias,
      ),
      owner: concrete_instance_super_owner(runtime_owner, signature_base_name, source_def),
      wrong_owner: concrete_instance_super_owner(runtime_owner, wrong_signature_base_name, source_def),
      same_arena: @function_def_arenas[forged_alias]?.try(&.same?(source_arena)) || false,
      wrong_owner_same_arena: @function_def_arenas[wrong_owner_alias]?.try(&.same?(source_arena)) || false,
    }
  end
end

private def binary_owner_fixture(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(arena, sources_by_arena: {arena.object_id.to_u64 => source})
  converter.no_prelude = true
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    end
  end
  program.roots.each do |id|
    node = arena[id]
    converter.lower_def(node) if node.is_a?(Adamas::Compiler::Frontend::DefNode)
  end
  converter.__test_drain_binary_owner_bodies
  converter
end

private def binary_owner_calls(converter : Adamas::HIR::AstToHir, name : String) : Array(String)
  function = converter.module.functions.find { |entry| entry.name.starts_with?(name) }.not_nil!
  function.blocks.flat_map(&.instructions).compact_map(&.as?(Adamas::HIR::Call)).map(&.method_name)
end

describe "concrete binary value owners" do
  it "materializes only the requested value owner from an inherited source body" do
    converter = binary_owner_fixture(<<-CRYSTAL)
      abstract struct BinaryValueParent
        def +(other : Int32) : Int32
          payload + other
        end
      end
      struct BinaryValueConcrete < BinaryValueParent
        def payload : Int32
          64
        end
      end
      def observe_binary_value(value : BinaryValueConcrete) : Int32
        value + 1
      end
    CRYSTAL
    binary_owner_calls(converter, "observe_binary_value$").should contain("BinaryValueConcrete#+$Int32")
    binary_owner_calls(converter, "BinaryValueConcrete#+$Int32").should contain("BinaryValueConcrete#payload")
    converter.module.functions.any? { |function| function.name.starts_with?("BinaryValueParent#+") }.should be_false
  end

  it "resolves super above the selected source owner while keeping the concrete body" do
    converter = binary_owner_fixture(<<-CRYSTAL)
      abstract struct BinaryValueGrandparent
        def +(other : Int32) : Int32
          1
        end
      end
      abstract struct BinaryValueParent < BinaryValueGrandparent
        abstract def payload : Int32
        def +(other : Int32) : Int32
          payload + super
        end
      end
      struct BinaryValueConcrete < BinaryValueParent
        def payload : Int32
          64
        end
      end
      def observe_binary_super(value : BinaryValueConcrete) : Int32
        value + 1
      end
    CRYSTAL
    binary_owner_calls(converter, "observe_binary_super$").should contain("BinaryValueConcrete#+$Int32")
    calls = binary_owner_calls(converter, "BinaryValueConcrete#+$Int32")
    calls.should contain("BinaryValueConcrete#payload")
    calls.should contain("BinaryValueGrandparent#+$Int32_super")
    calls.should_not contain("BinaryValueParent#+$Int32_super")
  end

  it "retains the ancestor target for ordinary inherited reference methods" do
    converter = binary_owner_fixture(<<-CRYSTAL)
      class BinaryReferenceParent
        def +(other : Bool) : Int32
          65
        end
      end
      class BinaryReferenceChild < BinaryReferenceParent
      end
      def observe_binary_reference(value : BinaryReferenceChild) : Int32
        value + true
      end
    CRYSTAL
    binary_owner_calls(converter, "observe_binary_reference$").should contain("BinaryReferenceParent#+$Bool")
  end

  it "keeps ordinary reference super lookup anchored at the source class" do
    converter = binary_owner_fixture(<<-CRYSTAL)
      abstract class BinaryReferenceGrandparent
        def +(other : Bool) : Int32
          65
        end
      end
      class BinaryReferenceParent < BinaryReferenceGrandparent
        def +(other : Bool) : Int32
          super
        end
      end
      class BinaryReferenceChild < BinaryReferenceParent
      end
      def observe_binary_reference(value : BinaryReferenceChild) : Int32
        value + true
      end
    CRYSTAL
    binary_owner_calls(converter, "observe_binary_reference$").should contain("BinaryReferenceParent#+$Bool")
    binary_owner_calls(converter, "BinaryReferenceParent#+$Bool").should contain("BinaryReferenceGrandparent#+$Bool_super")
  end

  it "keeps an explicit reference override selected" do
    converter = binary_owner_fixture(<<-CRYSTAL)
      class BinaryReferenceParent
        def +(other : Bool) : Int32
          65
        end
      end
      class BinaryReferenceChild < BinaryReferenceParent
        def +(other : Bool) : Int32
          66
        end
      end
      def observe_binary_reference(value : BinaryReferenceChild) : Int32
        value + true
      end
    CRYSTAL
    binary_owner_calls(converter, "observe_binary_reference$").should contain("BinaryReferenceChild#+$Bool")
  end

  it "ignores a forged same-Def runtime alias when recording the source owner" do
    converter = binary_owner_fixture(<<-CRYSTAL)
      class BinaryOwnerAuthenticityParent
        def probe(value : Int32) : Int32
          value
        end
      end
      class BinaryOwnerAuthenticityChild < BinaryOwnerAuthenticityParent
      end
      class BinaryOwnerAuthenticityOther
      end
      def observe_binary_owner_authenticity(value : BinaryOwnerAuthenticityChild) : Int32
        value.probe(1)
      end
    CRYSTAL
    resolution = converter.__test_binary_owner_alias_resolution(
      "BinaryOwnerAuthenticityParent#probe",
      "BinaryOwnerAuthenticityChild",
      "BinaryOwnerAuthenticityChild#probe_super",
      "BinaryOwnerAuthenticityOther#probe$Int32",
      "BinaryOwnerAuthenticityOther#probe",
    )

    resolution[:preferred_name].should eq("BinaryOwnerAuthenticityChild#probe_super")
    resolution[:canonical_name].should start_with("BinaryOwnerAuthenticityParent#probe")
    resolution[:same_arena].should be_true
    resolution[:wrong_owner_preferred_name].should eq("BinaryOwnerAuthenticityOther#probe$Int32")
    resolution[:wrong_owner_same_arena].should be_true
    resolution[:owner].should eq("BinaryOwnerAuthenticityParent")
    resolution[:wrong_owner].should be_nil
  end
end
