require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_aliased_block_signature(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(
    program.arena,
    sources_by_arena: {program.arena.object_id.to_u64 => source},
  )
  converter.arena = program.arena
  converter.no_prelude = true
  main = [] of UInt64
  program.roots.each do |root|
    case node = program.arena[root]
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    when Adamas::Compiler::Frontend::AliasNode
      converter.register_alias(node)
    else
      main << root.index.to_u64
    end
  end
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

private def aliased_block_callbacks(converter : Adamas::HIR::AstToHir)
  converter.module.functions.select { |function| function.name.starts_with?("__crystal_block_proc_") }
end

describe "aliased block signature inputs" do
  {"Proc(Int32, Input, Int32)", "Int32, Input -> Int32"}.each do |signature|
    it "retains the declaration namespace through an included #{signature} alias" do
      converter = lower_aliased_block_signature(<<-SOURCE)
        module SignatureLibrary
          alias Input = UInt64
          alias Action = #{signature}
          def capture(&callback : Action)
            callback.call(3, 19_u64)
          end
        end
        class SignatureUser
          include SignatureLibrary
          alias Input = String
          alias Action = Proc(Bool, Bool, Bool)
          def run
            capture { |value, input| value }
          end
        end
        SignatureUser.new.run
      SOURCE
      callbacks = aliased_block_callbacks(converter)
      callbacks.size.should eq(1)
      callback = callbacks.first
      callback.params.reject { |param| param.name == "__closure_env" }.map(&.type)
        .should eq([Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::UINT64])
      callback.return_type.should eq(Adamas::HIR::TypeRef::INT32)
    end
  end

  it "expands a chain of aliases without inventing inputs for an empty signature" do
    converter = lower_aliased_block_signature(<<-SOURCE)
      module EmptySignatureLibrary
        alias BaseAction = Proc(Bool)
        alias Action = BaseAction
        def capture(&callback : Action)
          callback.call
        end
      end
      class EmptySignatureUser
        include EmptySignatureLibrary
        def run
          capture { true }
        end
      end
      EmptySignatureUser.new.run
    SOURCE
    callbacks = aliased_block_callbacks(converter)
    callbacks.size.should eq(1)
    callback = callbacks.first
    callback.params.reject { |param| param.name == "__closure_env" }.should be_empty
    callback.return_type.should eq(Adamas::HIR::TypeRef::BOOL)
  end

  it "retains an included initializer's aliased input and Nil-result contract" do
    converter = lower_aliased_block_signature(<<-SOURCE)
      module ConstructorSignatureLibrary
        alias Action = Proc(Int32, UInt64, Nil)
        def initialize(&@callback : Action)
        end
      end
      class ConstructorSignatureUser
        include ConstructorSignatureLibrary
        alias Action = Proc(Bool, Bool)
      end
      ConstructorSignatureUser.new { |value| value }
    SOURCE
    callback = aliased_block_callbacks(converter).first
    callback.params.reject { |param| param.name == "__closure_env" }.map(&.type)
      .should eq([Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::UINT64])
    callback.return_type.should eq(Adamas::HIR::TypeRef::NIL)
  end

  it "preserves the existing concrete block annotation path" do
    converter = lower_aliased_block_signature(<<-SOURCE)
      def capture(&callback : Int32, UInt64 -> Int32)
        callback.call(3, 19_u64)
      end
      capture { |value, input| value }
    SOURCE
    callback = aliased_block_callbacks(converter).first
    callback.params.reject { |param| param.name == "__closure_env" }.map(&.type)
      .should eq([Adamas::HIR::TypeRef::INT32, Adamas::HIR::TypeRef::UINT64])
    callback.return_type.should eq(Adamas::HIR::TypeRef::INT32)
  end
end
