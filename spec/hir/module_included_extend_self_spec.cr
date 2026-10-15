require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_included_module_self_lookup(code : String) : Adamas::HIR::AstToHir
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

describe "Included module methods under extend self" do
  it "materializes private and public macro overloads through include and extend self" do
    source = <<-CRYSTAL
      module IncludedLookupSource
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

      module IncludedLookupConsumer
        include IncludedLookupSource
        extend self
      end

      IncludedLookupConsumer.narrow(41)
      IncludedLookupConsumer.wide(41_i64)
      IncludedLookupConsumer.public_value(41)
      IncludedLookupConsumer.public_value(41_i64)
    CRYSTAL
    converter = lower_included_module_self_lookup(source)
    {"Int32" => Adamas::HIR::TypeRef::INT32, "Int64" => Adamas::HIR::TypeRef::INT64}.each do |type, expected_return_type|
      %w(range_value public_value).each do |method|
        target = "IncludedLookupConsumer.#{method}$#{type}"
        converter.module.has_function_with_body?(target).should be_true, "#{target}: #{converter.module.functions.map(&.name).join(", ")}"
        function = converter.module.function_by_name(target).not_nil!
        function.return_type.should eq(expected_return_type)
      end
    end
  end

  it "exports included definitions from a source with extend self" do
    converter = lower_included_module_self_lookup(<<-CRYSTAL)
      module IncludedSelfSource
        extend self
        {% for type in [Int32, Int64] %}
          def generated(value : {{type}}) : {{type}}
            value + 2
          end
        {% end %}
      end
      module IncludedSelfConsumer
        include IncludedSelfSource
        extend self
      end
      IncludedSelfConsumer.generated(41)
      IncludedSelfConsumer.generated(41_i64)
    CRYSTAL
    {"Int32" => Adamas::HIR::TypeRef::INT32, "Int64" => Adamas::HIR::TypeRef::INT64}.each do |type, return_type|
      target = "IncludedSelfConsumer.generated$#{type}"
      converter.module.has_function_with_body?(target).should be_true, target
      converter.module.function_by_name(target).not_nil!.return_type.should eq(return_type)
    end
  end
  it "exports ordinary included methods from a nested module" do
    converter = lower_included_module_self_lookup(<<-CRYSTAL)
      module IncludedNested
        module Source
          def value(input : Int32) : Int32
            input + 1
          end
        end
        module Consumer
          include Source
          extend self
        end
      end
      IncludedNested::Consumer.value(41)
    CRYSTAL
    target = "IncludedNested::Consumer.value$Int32"
    converter.module.has_function_with_body?(target).should be_true, target
    converter.module.function_by_name(target).not_nil!.return_type.should eq(Adamas::HIR::TypeRef::INT32)
  end

end
