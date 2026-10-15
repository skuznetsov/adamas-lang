require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_generated_module_lookup(code : String) : Adamas::HIR::AstToHir
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

describe "Retained generated module methods" do
  it "materializes private and public macro overloads through an extended module" do
    source = <<-CRYSTAL
      module GeneratedLookupSource
        {% for type in [Int32, Int64] %}
          private def range_value(value : {{type}}) : {{type}}
            value + 1
          end
          def public_value(value : {{type}}) : {{type}}
            value + 2
          end
        {% end %}

        def narrow(value : Int32) : Int32
          range_value(value)
        end

        def wide(value : Int64) : Int64
          range_value(value)
        end
      end

      module GeneratedLookupConsumer
        extend GeneratedLookupSource
        extend self
      end

      GeneratedLookupConsumer.narrow(41)
      GeneratedLookupConsumer.wide(41_i64)
      GeneratedLookupConsumer.public_value(41)
      GeneratedLookupConsumer.public_value(41_i64)
    CRYSTAL
    converter = lower_generated_module_lookup(source)
    {"Int32" => Adamas::HIR::TypeRef::INT32, "Int64" => Adamas::HIR::TypeRef::INT64}.each do |type, expected_return_type|
      %w(range_value public_value).each do |method|
        target = "GeneratedLookupConsumer.#{method}$#{type}"
        converter.module.has_function_with_body?(target).should be_true, "#{target}: #{converter.module.functions.map(&.name).join(", ")}"
        function = converter.module.function_by_name(target).not_nil!
        function.return_type.should eq(expected_return_type)
      end
    end
  end

  it "exports generated instance definitions from a source with extend self" do
    converter = lower_generated_module_lookup(<<-CRYSTAL)
      module GeneratedSelfSource
        extend self
        {% for type in [Int32, Int64] %}
          def generated(value : {{type}}) : {{type}}
            value + 2
          end
        {% end %}
      end
      module GeneratedSelfConsumer
        extend GeneratedSelfSource
        extend self
      end
      GeneratedSelfConsumer.generated(41)
      GeneratedSelfConsumer.generated(41_i64)
    CRYSTAL
    {"Int32" => Adamas::HIR::TypeRef::INT32, "Int64" => Adamas::HIR::TypeRef::INT64}.each do |type, return_type|
      target = "GeneratedSelfConsumer.generated$#{type}"
      converter.module.has_function_with_body?(target).should be_true, target
      converter.module.function_by_name(target).not_nil!.return_type.should eq(return_type)
    end
  end
end
