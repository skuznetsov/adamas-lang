require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_monomorphize_qualified_ivar_owner(
    base_name : String,
    type_args : Array(String),
    specialized_name : String,
  ) : Nil
    monomorphize_generic_class(base_name, type_args, specialized_name)
  end

  def __test_qualified_ivar_type_names(owner_name : String) : Hash(String, String)
    types = {} of String => String
    @class_info[owner_name].ivars.each do |ivar|
      types[ivar.name] = get_type_name_from_ref(ivar.type)
    end
    types
  end

  def __test_extract_source_type_name(expr_id : Adamas::Compiler::Frontend::ExprId) : String?
    node = node_for_expr(expr_id, @arena)
    node ? extract_type_name_from_node(node) : nil
  end
end

private def register_qualified_generic_ivar_program(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty

  converter = Adamas::HIR::AstToHir.new(program.arena)
  converter.no_prelude = true
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end
  converter
end

describe "qualified generic constructor ivar inference" do
  it "resolves relative, rooted, and unqualified generic constructors at field birth" do
    converter = register_qualified_generic_ivar_program(<<-CRYSTAL)
      module QualifiedGenericIvarInference
        class LocalBox(U)
        end

        module Deep
          class Payload(V)
          end

          class Box(V)
          end
        end

        class Holder(T)
          def initialize
            @local = LocalBox(T).new
            @relative = Deep::Box(Deep::Payload(T)).new
            @rooted = ::QualifiedGenericIvarInference::Deep::Box(
              ::QualifiedGenericIvarInference::Deep::Payload(T)
            ).new
          end
        end
      end
    CRYSTAL

    owner_name = "QualifiedGenericIvarInference::Holder(Int32)"
    converter.__test_monomorphize_qualified_ivar_owner(
      "QualifiedGenericIvarInference::Holder",
      ["Int32"],
      owner_name,
    )

    # Registration infers the class layout before lowering initialize.
    converter.__test_qualified_ivar_type_names(owner_name).should eq({
      "@local"    => "QualifiedGenericIvarInference::LocalBox(Int32)",
      "@relative" => "QualifiedGenericIvarInference::Deep::Box(QualifiedGenericIvarInference::Deep::Payload(Int32))",
      "@rooted"   => "QualifiedGenericIvarInference::Deep::Box(QualifiedGenericIvarInference::Deep::Payload(Int32))",
    })
  end

  it "does not extract a lowercase qualified runtime call as a type name" do
    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("::QualifiedGenericIvarInference::factory(Int32)"),
    )
    program = parser.parse_program
    parser.diagnostics.should be_empty

    call = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::CallNode)
    callee = program.arena[call.callee].as(Adamas::Compiler::Frontend::PathNode)
    callee.left.should_not be_nil

    converter = Adamas::HIR::AstToHir.new(program.arena)
    converter.no_prelude = true
    converter.__test_extract_source_type_name(program.roots.first).should be_nil
  end
end
