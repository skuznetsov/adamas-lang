require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __generated_cvar_test_type_ref_for_module_classvar(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end

  def __generated_cvar_test_type_name_for_module_classvar(type : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type)
  end

  def __generated_cvar_test_type_alias_target_for_module_classvar(name : String) : String?
    @type_aliases[name]?
  end

  def __generated_cvar_test_module_macro_function_names(prefix : String) : Array(String)
    @function_defs.keys.select(&.starts_with?(prefix))
  end

  def __generated_cvar_test_module_macro_deferred_classvar_names : Array(String)
    @deferred_classvar_inits.compact_map do |entry|
      extract_deferred_classvar_name(entry.arena, entry.expr_id)
    end
  end

  def __generated_cvar_test_register_module_macro_expansion(
    owner_name : String,
    arena : Adamas::Compiler::Frontend::AstArena |
            Adamas::Compiler::Frontend::PageArena |
            Adamas::Compiler::Frontend::VirtualArena,
    expr_id : Adamas::Compiler::Frontend::ExprId,
  ) : Nil
    previous_arena = @arena.not_nil!
    @arena = arena
    register_module_members_from_macro_expansion(owner_name, expr_id)
  ensure
    @arena = previous_arena.as(Adamas::Compiler::Frontend::ArenaLike)
  end
end

private def register_generated_module_classvar_fixture(source : String) : Adamas::HIR::AstToHir
  lexer = Adamas::Compiler::Frontend::Lexer.new(source)
  parser = Adamas::Compiler::Frontend::Parser.new(lexer)
  program = parser.parse_program
  arena = parser.arena
  converter = Adamas::HIR::AstToHir.new(arena)
  converter.arena = arena

  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    end
  end

  converter
end

describe "module macro class variable registration" do
  it "keeps the class-macro registration control and direct module declaration" do
    converter = register_generated_module_classvar_fixture(<<-CRYSTAL)
      class MacroClassVarRegistrationControl
        macro declare_value
          @@value : Int32
        end

        declare_value
      end

      module DirectModuleClassVarRegistrationControl
        @@value : Int32
      end
    CRYSTAL

    class_vars = converter.class_info["MacroClassVarRegistrationControl"].class_vars
    class_vars.map(&.name).should contain("value")
    class_vars.find!(&.name.==("value")).type.should eq(Adamas::HIR::TypeRef::INT32)

    module_vars = converter.module_class_vars["DirectModuleClassVarRegistrationControl"]
    module_vars.map(&.name).should contain("value")
    module_vars.find!(&.name.==("value")).type.should eq(Adamas::HIR::TypeRef::INT32)
  end

  it "registers macro-expanded module classvar declarations with primitive and generic types" do
    converter = register_generated_module_classvar_fixture(<<-CRYSTAL)
      module MacroModuleClassVarRegistration
        macro declare_value(name, type)
          @@{{name.id}} : {{type}}
        end

        declare_value value, Int32
        declare_value pointer, Pointer(UInt8)

        macro define_nullable_value
          @@nullable : Int32 | Nil
          def self.nullable : Int32?
            @@nullable
          end
        end

        define_nullable_value

        macro define_count
          @@count : Int32
        end

        define_count

        macro define_marker
          def self.marker : Int32
            1
          end
        end

        define_marker
      end

      module MacroNestedModuleClassVarRegistration
        module Left
          macro declare_shared
            @@shared : Int32 | Nil
          end

          declare_shared
        end

        module Right
          macro declare_shared
            @@shared : Pointer(UInt8)
          end

          declare_shared
        end
      end
    CRYSTAL

    converter.__generated_cvar_test_module_macro_function_names("MacroModuleClassVarRegistration.marker").should_not be_empty
    converter.__generated_cvar_test_module_macro_function_names("MacroModuleClassVarRegistration.nullable").should_not be_empty

    module_vars = converter.module_class_vars["MacroModuleClassVarRegistration"]? ||
                  [] of Adamas::HIR::ClassVarInfo
    module_vars.map(&.name).should contain("value")
    module_vars.map(&.name).should contain("pointer")
    module_vars.map(&.name).should contain("nullable")
    module_vars.map(&.name).should contain("count")
    module_vars.find!(&.name.==("value")).type.should eq(Adamas::HIR::TypeRef::INT32)
    module_vars.find!(&.name.==("pointer")).type.should eq(
      converter.__generated_cvar_test_type_ref_for_module_classvar("Pointer(UInt8)"),
    )
    module_vars.find!(&.name.==("nullable")).type.should eq(
      converter.__generated_cvar_test_type_ref_for_module_classvar("Int32 | Nil"),
    )
    module_vars.find!(&.name.==("count")).type.should eq(Adamas::HIR::TypeRef::INT32)

    left_vars = converter.module_class_vars["MacroNestedModuleClassVarRegistration::Left"]
    right_vars = converter.module_class_vars["MacroNestedModuleClassVarRegistration::Right"]
    left_vars.find!(&.name.==("shared")).type.should eq(
      converter.__generated_cvar_test_type_ref_for_module_classvar("Int32 | Nil"),
    )
    right_vars.find!(&.name.==("shared")).type.should eq(
      converter.__generated_cvar_test_type_ref_for_module_classvar("Pointer(UInt8)"),
    )
  end

  it "records macro-expanded declarations and defers non-literal initializers" do
    converter = register_generated_module_classvar_fixture(<<-CRYSTAL)
      module MacroModuleClassVarInitializerRegistration
      end
    CRYSTAL

    lexer = Adamas::Compiler::Frontend::Lexer.new(<<-CRYSTAL)
      module MacroModuleClassVarInitializerRegistration
        @@numbered : Int32 = 7
        @@deferred : String = initializer_side_effect
      end
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(lexer)
    program = parser.parse_program
    arena = parser.arena
    module_node = arena[program.roots.first].as(Adamas::Compiler::Frontend::ModuleNode)
    body = module_node.body.not_nil!

    body.each do |expr_id|
      converter.__generated_cvar_test_register_module_macro_expansion(
        "MacroModuleClassVarInitializerRegistration",
        arena,
        expr_id,
      )
    end

    module_vars = converter.module_class_vars["MacroModuleClassVarInitializerRegistration"]
    module_vars.find!(&.name.==("numbered")).initial_value.should eq(7_i64)
    module_vars.find!(&.name.==("deferred")).type.should eq(Adamas::HIR::TypeRef::STRING)
    converter.__generated_cvar_test_module_macro_deferred_classvar_names.count("deferred").should eq(1)
  end

end
