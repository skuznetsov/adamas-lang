require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_pointerof_layout_program(code : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(code))
  result = parser.parse_program
  converter = Adamas::HIR::AstToHir.new(result.arena)
  converter.arena = result.arena

  classes = [] of Adamas::Compiler::Frontend::ClassNode
  result.roots.each do |expr_id|
    node = result.arena[expr_id]
    classes << node if node.is_a?(Adamas::Compiler::Frontend::ClassNode)
  end

  classes.each { |node| converter.register_class(node) }
  classes.each { |node| converter.lower_class(node) }
  converter
end

private def pointerof_layout_text(function : Adamas::HIR::Function) : String
  String.build { |io| function.to_s(io) }
end

describe "pointerof instance-variable layout" do
  it "uses the canonical String payload offset without changing ordinary ivar offsets" do
    converter = lower_pointerof_layout_program(<<-CRYSTAL)
      class String
        def to_unsafe : UInt8*
          pointerof(@c)
        end
      end

      class Buffer
        getter head : Int32
        getter payload : UInt8

        def payload_ptr : UInt8*
          pointerof(@payload)
        end
      end

      class StringHeaderProbe
        getter bytesize : Int32
        getter size : Int32
        getter payload : UInt8

        def payload_ptr : UInt8*
          pointerof(@payload)
        end
      end
    CRYSTAL

    string_fn = converter.module.functions.find { |candidate| candidate.name.starts_with?("String#to_unsafe") }
    string_fn.should_not be_nil
    string_text = pointerof_layout_text(string_fn.not_nil!)
    string_text.should contain("literal 12 : Int64")
    string_text.should contain("ptr_add")

    buffer_fn = converter.module.functions.find { |candidate| candidate.name.starts_with?("Buffer#payload_ptr") }
    buffer_fn.should_not be_nil
    buffer_text = pointerof_layout_text(buffer_fn.not_nil!)
    buffer_text.should contain("literal 8 : Int64")
    buffer_text.should contain("ptr_add")

    header_probe_fn = converter.module.functions.find { |candidate| candidate.name.starts_with?("StringHeaderProbe#payload_ptr") }
    header_probe_fn.should_not be_nil
    header_probe_text = pointerof_layout_text(header_probe_fn.not_nil!)
    header_probe_text.should contain("literal 12 : Int64")
    header_probe_text.should contain("ptr_add")
  end
end
