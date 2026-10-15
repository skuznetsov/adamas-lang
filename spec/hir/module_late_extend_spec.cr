require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_late_module_exports(code : String) : Adamas::HIR::AstToHir
  parsed = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(code),
  ).parse_program
  arena = parsed.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => code},
  )
  converter.arena = arena
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  main = [] of UInt64
  parsed.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      modules << node
    when Adamas::Compiler::Frontend::CallNode
      main << id.index.to_u64
    end
  end
  modules.each { |node| converter.register_module(node) }
  modules.each { |node| converter.lower_module(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

describe "Late module exports" do
  it "retains class dispatch when an extended module is reopened later" do
    converter = lower_late_module_exports(<<-CRYSTAL)
      module LateExportSource
      end
      module LateExportConsumer
        extend LateExportSource
        extend self
      end
      module LateExportSource
        {% for type in [Int32, Int64] %}
          private def hidden(value : {{type}}) : {{type}}
            value + 1
          end
        {% end %}
        def narrow(value : Int32) : Int32
          hidden(value)
        end
        def wide(value : Int64) : Int64
          hidden(value)
        end
      end
      LateExportConsumer.narrow(41)
      LateExportConsumer.wide(41_i64)
    CRYSTAL
    {"Int32" => Adamas::HIR::TypeRef::INT32, "Int64" => Adamas::HIR::TypeRef::INT64}.each do |type, result_type|
      name = "LateExportConsumer.hidden$#{type}"
      converter.module.has_function_with_body?(name).should be_true, name
      function = converter.module.function_by_name(name).not_nil!
      function.return_type.should eq(result_type)
      function.params.size.should eq(1)
    end
    {"narrow" => "Int32", "wide" => "Int64"}.each do |method, type|
      name = "LateExportConsumer.#{method}$#{type}"
      function = converter.module.function_by_name(name).not_nil!
      function.params.size.should eq(1)
      function.blocks.flat_map(&.instructions).select(Adamas::HIR::Call).any? do |call|
        call.method_name == "LateExportConsumer.hidden$#{type}" && call.receiver.nil?
      end.should be_true
    end
  end
end
