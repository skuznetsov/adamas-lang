require "spec"

require "../../src/compiler/frontend/parser"

# A parenthesized proc type may omit its return type: `(A, B) ->`. The stdlib
# writes block restrictions this way (Crystal::EventLoop::Polling::Arena#allocate_at?
# takes `& : (Pointer(T), Index) ->`). The parser used to reject the missing
# return type and resume the fallback type parser mid-type, so the parameter
# kept an empty annotation and a span over unrelated source; prelude hello then
# resolved a phantom `Index` from that span.
private def parse_def_params(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  def_node = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::DefNode)
  def_node.params.not_nil!
end

private def annotation_of(param) : String
  String.new(param.type_annotation.not_nil!)
end

private def type_span_text(source : String, param) : String
  span = param.type_span.not_nil!
  source.byte_slice(span.start_offset, span.end_offset - span.start_offset)
end

describe "parenthesized proc type annotations" do
  it "keeps an anonymous block restriction without return type" do
    source = "def alloc(i : Int32, & : (Pointer(T), Index) ->) : Index\nend\n"
    params = parse_def_params(source)
    params.size.should eq(2)
    params[1].is_block.should be_true
    annotation_of(params[1]).should eq("(Pointer(T), Index) ->")
    type_span_text(source, params[1]).should eq("(Pointer(T), Index) ->")
  end

  it "keeps a named block restriction without return type" do
    source = "def each(&blk : (Int32) ->)\nend\n"
    params = parse_def_params(source)
    params[0].is_block.should be_true
    annotation_of(params[0]).should eq("(Int32) ->")
    type_span_text(source, params[0]).should eq("(Int32) ->")
  end

  it "keeps a proc-typed regular parameter and the parameter after it" do
    source = "def call_it(cb : (Int32, Int32) ->, v : Int32)\nend\n"
    params = parse_def_params(source)
    params.size.should eq(2)
    annotation_of(params[0]).should eq("(Int32, Int32) ->")
    type_span_text(source, params[0]).should eq("(Int32, Int32) ->")
    String.new(params[1].name.not_nil!).should eq("v")
    annotation_of(params[1]).should eq("Int32")
  end

  it "keeps an arrow inside the parentheses without return type" do
    source = "def each(& : (Int32, Int32 ->))\nend\n"
    params = parse_def_params(source)
    annotation_of(params[0]).should eq("(Int32, Int32 ->)")
  end

  it "still parses return types and bare proc types" do
    params = parse_def_params("def m(& : (Int32) -> Int32)\nend\n")
    annotation_of(params[0]).should eq("(Int32) -> Int32")

    params = parse_def_params("def m(& : Pointer(T), Index ->)\nend\n")
    annotation_of(params[0]).should eq("Pointer(T), Index ->")
  end

  it "still reports an unclosed parenthesized type" do
    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new("def m(cb : (Int32, Int32 ->\nend\n"))
    parser.parse_program
    parser.diagnostics.should_not be_empty
  end
end
