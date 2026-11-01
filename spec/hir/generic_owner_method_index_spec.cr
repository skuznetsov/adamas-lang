require "spec"
require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"

class Adamas::HIR::AstToHir
  def __test_filter_method_candidates(
    candidates : Array(String),
    requested_owner : String,
    separator : Char = '#',
  ) : Array(String)
    filter_method_index_candidates_for_owner(candidates, requested_owner, separator)
  end

  def __test_type_parameter_only(arg : String, declared_params : Array(String)) : Bool
    method_index_type_parameter_only?(arg, declared_params)
  end

  def __test_receiver_repair_fallback_lookup_name(owner : String, fallback_base : String) : String
    request = ReceiverRepairFallback.new(
      "#{owner}#[]$Int32_Int32",
      fallback_base,
      owner,
      [] of Adamas::HIR::TypeRef,
      false,
      false,
      false,
      "test",
    )
    receiver_repair_fallback_lookup_name(request)
  end
end

describe "generic method-index owner filtering" do
  it "prefers the exact owner over template and bare fallbacks while rejecting concrete siblings" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    candidates = [
      "Array(Time::Location::ZoneTransition)#fetch$Int32_Nil",
      "Array(Hash(String, UInt32))#fetch$Int32_Nil",
      "Array(T)#fetch$Int32_Nil",
      "Array#fetch$Int32_Nil",
      "Indexable(T)#fetch$Int32_Nil",
    ]

    selected = converter.__test_filter_method_candidates(
      candidates,
      "Array(Hash(String, UInt32))",
    )

    selected.should eq([
      "Array(Hash(String, UInt32))#fetch$Int32_Nil",
    ])
  end

  it "preserves inherited module templates and separator ownership" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    candidates = [
      "Indexable(T)#fetch$Int32_Nil",
      "Indexable#fetch$Int32_Nil",
      "Indexable(T).fetch$Int32_Nil",
    ]

    converter.__test_filter_method_candidates(candidates, "Indexable(String)").should eq([
      "Indexable(T)#fetch$Int32_Nil",
      "Indexable#fetch$Int32_Nil",
    ])
    converter.__test_filter_method_candidates(candidates, "Indexable(String)", '.').should eq([
      "Indexable(T).fetch$Int32_Nil",
    ])
  end

  it "leaves non-generic lookup buckets unchanged" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    candidates = [
      "Array(Time)#fetch$Int32_Nil",
      "Array(Hash(String, UInt32))#fetch$Int32_Nil",
    ]
    converter.__test_filter_method_candidates(candidates, "Array").should eq(candidates)
  end

  it "accepts only the supplied declared type parameters" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_type_parameter_only("T", ["T"]).should be_true
    converter.__test_type_parameter_only("X", ["T"]).should be_false
    converter.__test_type_parameter_only("Array(T)", ["T"]).should be_true
    converter.__test_type_parameter_only("Array(String)", ["T"]).should be_false

    deep = "Array(" * 10 + "T" + ")" * 10
    converter.__test_type_parameter_only(deep, ["T"]).should be_true
  end

  it "formats same-family receiver repair fallback keys without changing ancestors" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)

    converter.__test_receiver_repair_fallback_lookup_name(
      "Slice(Pointer(Event))",
      "Slice#[]",
    ).should eq("Slice(Pointer(Event))#[]")
    converter.__test_receiver_repair_fallback_lookup_name(
      "Array(Hash(String, UInt32))",
      "Array#fetch",
    ).should eq("Array(Hash(String, UInt32))#fetch")
    converter.__test_receiver_repair_fallback_lookup_name(
      "Array(Hash(String, UInt32))",
      "Indexable#fetch",
    ).should eq("Indexable#fetch")
  end
end


describe "resolved generic method owners" do
  it "matches rooted nested Proc children without admitting another concrete receiver" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    correct = "Array(Proc(Int32, Nil | Exception, Nil))#pop$block"
    candidates = ["Array(String)#pop$block", correct, "Array(T)#pop$block"]
    converter.__test_filter_method_candidates(
      candidates, "Array(Proc(::Int32, ::Nil | ::Exception, ::Nil))",
    ).should eq([correct])
  end

  it "matches rooted Tuple children and retains distinct qualified child identities" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    correct = "Box(Tuple(Int32, Domain::Item))#value"
    candidates = ["Box(Tuple(Int32, Other::Item))#value", correct]
    converter.__test_filter_method_candidates(
      candidates, "Box(Tuple(::Int32, ::Domain::Item))",
    ).should eq([correct])
  end
end


describe "generic owner exactness adversaries" do
  it "keeps a declared template formal separate from an explicitly rooted nominal type" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_filter_method_candidates(
      ["Array(T)#pop$block", "Array(::T)#pop$block"], "Array(::T)",
    ).should eq(["Array(::T)#pop$block"])
  end

  it "keeps an already resolved nested owner distinct from its root namesake" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    correct = "Box(Outer::Domain::Item)#value"
    converter.__test_filter_method_candidates(
      ["Box(Domain::Item)#value", correct], "Box(::Outer::Domain::Item)",
    ).should eq([correct])
  end
end


class Adamas::HIR::AstToHir
  def __test_resolve_registered_owner_candidates(candidates : Array(String), requested : String) : String?
    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("def item; 1; end"),
    )
    program = parser.parse_program
    parser.diagnostics.should be_empty
    definition = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::DefNode)
    with_arena(program.arena) do
      candidates.each do |candidate|
        set_function_def_entry(candidate, definition, record_current_arena: false)
        set_function_def_arena(candidate, program.arena)
      end
      lookup_function_def_for_call(requested, 0, false, [] of TypeRef).try(&.[0])
    end
  end
end

describe "generic owner resolver fallback admission" do
  it "rejects a concrete sibling recovered through the stripped overload family" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_resolve_registered_owner_candidates(
      ["Owner(String)#item"], "Owner(Bool)#item",
    ).should be_nil
  end

  it "selects a concrete rooted composite from registered source keys" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    correct = "Owner(Proc(Int32, Nil | Exception, Nil))#item"
    converter.__test_resolve_registered_owner_candidates(
      ["Owner(String)#item", correct],
      "Owner(Proc(::Int32, ::Nil | ::Exception, ::Nil))#item",
    ).should eq(correct)
  end

  it "retains a declared generic template when the exact owner is not registered" do
    converter = Adamas::HIR::AstToHir.new(Adamas::Compiler::Frontend::AstArena.new)
    converter.__test_resolve_registered_owner_candidates(
      ["Array(String)#item", "Array(T)#item"], "Array(Bool)#item",
    ).should eq("Array(T)#item")
  end
end
