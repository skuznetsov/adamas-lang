require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_reflection_owner_has_ivar?(owner : String, name : String) : Bool
    @class_info[owner]?.try { |info| info.ivars.any? { |ivar| ivar.name == name } } || false
  end

  def __test_reflection_owner_has_function_type?(name : String) : Bool
    @function_types.has_key?(name)
  end

  def __test_reflection_owner_expand(owner_name : String, source : String) : String
    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    parser = Adamas::Compiler::Frontend::Parser.new(lexer)
    program = parser.parse_program
    parser.diagnostics.should be_empty
    expression_id = program.roots.first
    expression_id.should_not be_nil

    expander = Adamas::Compiler::Semantic::MacroExpander.new(
      program,
      program.arena,
      recovery_mode: true,
      macro_source: source
    )
    owner_type = macro_owner_type_for(owner_name)
    expander.expand_expression(
      expression_id.not_nil!,
      variables: {} of String => Adamas::Compiler::Semantic::MacroValue,
      owner_type: owner_type
    )
  end
end

describe "module macro declaration owner reflection" do
  it "uses the declaring module as the owner for thread_local macro reflection" do
    source = <<-CRYSTAL
      class Thread
        def self.current : Thread
          Thread.new
        end
      end

      class Object
        macro thread_local(decl, &constructor)
          {% name = decl.var.id %}
          {% tls_name = "__tls_\#{@type.name.gsub(/:/, "_")}__\#{name}".id %}
          @@{{name}} : {{decl.type}} | Nil

          def self.{{name}} : {{decl.type}}
            if (value = @@{{name}}).nil?
              Thread.current.{{tls_name}} = @@{{name}} = {{yield}}
            else
              value
            end
          end

          class ::Thread
            property {{tls_name}} : {{decl.type}} | Nil
          end
        end
      end

      module MacroThreadLocalModule
        thread_local(cached_value : Int32) do
          42
        end
      end

      puts Thread.current.__tls_MacroThreadLocalModule__cached_value
    CRYSTAL
    lexer = Adamas::Compiler::Frontend::Lexer.new(source)
    parser = Adamas::Compiler::Frontend::Parser.new(lexer)
    program = parser.parse_program
    arena = parser.arena
    converter = Adamas::HIR::AstToHir.new(arena)
    converter.arena = arena
    converter.seed_top_level_type_names(["Thread", "MacroThreadLocalModule"])

    defs = [] of Adamas::Compiler::Frontend::DefNode
    main_exprs = [] of UInt64
    program.roots.each do |root_id|
      case node = arena[root_id]
      when Adamas::Compiler::Frontend::ClassNode
        converter.register_class(node)
      when Adamas::Compiler::Frontend::ModuleNode
        converter.register_module(node)
      when Adamas::Compiler::Frontend::DefNode
        defs << node
      when Adamas::Compiler::Frontend::CallNode
        main_exprs << root_id.index.to_u64
      end
    end
    defs.each { |node| converter.register_function(node) }
    defs.each { |node| converter.lower_def(node) }
    converter.lower_main(main_exprs)

    converter.__test_reflection_owner_has_ivar?("Thread", "@__tls_MacroThreadLocalModule__cached_value").should be_true
    converter.__test_reflection_owner_has_ivar?("Thread", "@__tls___cached_value").should be_false
    converter.__test_reflection_owner_has_function_type?("Thread#__tls_MacroThreadLocalModule__cached_value").should be_true
    converter.module.has_function_with_body?("Thread#__tls_MacroThreadLocalModule__cached_value").should be_true
  end

  it "resolves value-position @type.name for a module macro owner" do
    module_source = <<-CRYSTAL
      module MacroTypeContextOwner
      end
      class MacroTypeContextClass
      end
      CRYSTAL
    lexer = Adamas::Compiler::Frontend::Lexer.new(module_source)
    parser = Adamas::Compiler::Frontend::Parser.new(lexer)
    program = parser.parse_program
    parser.diagnostics.should be_empty

    converter = Adamas::HIR::AstToHir.new(
      program.arena,
      sources_by_arena: {program.arena.object_id.to_u64 => module_source},
    )
    converter.arena = program.arena
    program.roots.each do |root_id|
      case node = program.arena[root_id]
      when Adamas::Compiler::Frontend::ModuleNode
        converter.register_module(node)
      when Adamas::Compiler::Frontend::ClassNode
        converter.register_class(node)
      end
    end

    converter.__test_reflection_owner_expand(
      "MacroTypeContextOwner",
      "{{ @type.name }}"
    ).should eq("MacroTypeContextOwner")
    converter.__test_reflection_owner_expand(
      "MacroTypeContextOwner",
      "{{ @type.module? }}"
    ).should eq("true")
    converter.__test_reflection_owner_expand(
      "MacroTypeContextOwner",
      "{{ @type.class? }}"
    ).should eq("false")
    converter.__test_reflection_owner_expand(
      "MacroTypeContextClass",
      "{{ @type.class? }}"
    ).should eq("true")
    converter.__test_reflection_owner_expand(
      "MacroTypeContextClass",
      "{{ @type.module? }}"
    ).should eq("false")
  end
end
