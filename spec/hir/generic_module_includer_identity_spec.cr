require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_includer_instantiate(owner : String, argument : String)
    monomorphize_generic_class(owner, [argument], "#{owner}(#{argument})")
  end
end

private def generic_module_includer_census(source : String, instantiate : Array(String) = [] of String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(parsed.arena,
    sources_by_arena: {parsed.arena.object_id.to_u64 => source})
  parsed.roots.each do |root|
    case node = parsed.arena[root]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  instantiate.each do |owner|
    converter.__test_includer_instantiate(owner, "Int32")
    converter.__test_includer_instantiate(owner, "Int64")
  end
  converter.module.module_includers
end

describe "applied generic module includer identity" do
  it "keeps different actual arguments in separate runtime includer sets" do
    census = generic_module_includer_census(<<-CRYSTAL)
      module AppliedView(T)
      end
      class Carrier32
        include AppliedView(Int32)
      end
      class Carrier64
        include AppliedView(Int64)
      end
    CRYSTAL
    census["AppliedView(Int32)"].should eq(["Carrier32"])
    census["AppliedView(Int64)"].should eq(["Carrier64"])
  end

  it "substitutes the type argument through a transitive module include" do
    census = generic_module_includer_census(<<-CRYSTAL)
      module AppliedView(T)
      end
      module AppliedRelay(U)
        include AppliedView(U)
      end
      class Relay32
        include AppliedRelay(Int32)
      end
      class Relay64
        include AppliedRelay(Int64)
      end
    CRYSTAL
    census["AppliedRelay(Int32)"].should eq(["Relay32"])
    census["AppliedView(Int32)"].should eq(["Relay32"])
    census["AppliedView(Int64)"].should eq(["Relay64"])
  end

  it "retains namespaces when modules have the same short name" do
    census = generic_module_includer_census(<<-CRYSTAL)
      module LeftScope
        module AppliedView(T)
        end
      end
      module RightScope
        module AppliedView(T)
        end
      end
      class LeftCarrier
        include LeftScope::AppliedView(Int32)
      end
      class RightCarrier
        include RightScope::AppliedView(Int32)
      end
    CRYSTAL
    census["LeftScope::AppliedView(Int32)"].should eq(["LeftCarrier"])
    census["RightScope::AppliedView(Int32)"].should eq(["RightCarrier"])
  end

  it "carries concrete arguments through an instantiated generic relay class" do
    census = generic_module_includer_census(<<-CRYSTAL, ["RelayCarrier"])
      module AppliedView(T)
      end
      module AppliedRelay(U)
        include AppliedView(U)
      end
      class RelayCarrier(V)
        include AppliedRelay(V)
      end
    CRYSTAL
    census["AppliedView(Int32)"].should eq(["RelayCarrier(Int32)"])
    census["AppliedView(Int64)"].should eq(["RelayCarrier(Int64)"])
  end

  it "retains both applied includers of a qualified generic module" do
    census = generic_module_includer_census(<<-CRYSTAL, ["QualifiedScope::Carrier"])
      module QualifiedScope
        module AppliedView(T)
        end
        class Carrier(U)
          include AppliedView(U)
        end
      end
    CRYSTAL
    census["QualifiedScope::AppliedView(Int32)"].should eq(["QualifiedScope::Carrier(Int32)"])
    census["QualifiedScope::AppliedView(Int64)"].should eq(["QualifiedScope::Carrier(Int64)"])
  end
end
