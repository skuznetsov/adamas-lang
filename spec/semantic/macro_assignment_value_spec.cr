require "spec"
require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/macro_expander"

private def macro_assignment_program(source : String)
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source), recovery_mode: false)
  program = parser.parse_program
  parser.diagnostics.should be_empty
  program
end

private def macro_assignment_value(source : String, variables : Hash(String, Adamas::Compiler::Semantic::MacroValue))
  program = macro_assignment_program(source)
  expander = Adamas::Compiler::Semantic::MacroExpander.new(program, program.arena)
  value = expander.evaluate_value(program.roots.first, variables: variables)
  expander.diagnostics.should be_empty
  value.not_nil!
end

private def macro_assignment_body(source : String, variables : Hash(String, Adamas::Compiler::Semantic::MacroValue))
  program = macro_assignment_program("macro assignment_probe\n#{source}\nend")
  definition = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::MacroDefNode)
  expander = Adamas::Compiler::Semantic::MacroExpander.new(program, program.arena)
  output = expander.expand_literal(definition.body, variables: variables)
  expander.diagnostics.should be_empty
  output.split.join(" ")
end

describe "macro assignment values" do
  it "preserves an unparenthesized assignment as a macro-if condition" do
    program = macro_assignment_program(<<-CRYSTAL)
      {% if ann = @type.annotation(Opt) %}
        {{ ann[:code] }}
      {% end %}
      CRYSTAL
    branch = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::MacroIfNode)
    condition = program.arena[branch.condition]
    condition.should be_a(Adamas::Compiler::Frontend::AssignNode)
    assignment = condition.as(Adamas::Compiler::Frontend::AssignNode)
    Adamas::Compiler::Frontend.node_literal_string(program.arena[assignment.target]).should eq("ann")
    program.arena[assignment.value].should be_a(Adamas::Compiler::Frontend::CallNode)
  end

  it "preserves if and elsif assignments in macro-body control pieces" do
    program = macro_assignment_program(<<-CRYSTAL)
      macro assignment_probe
        {% if first = nil %}
          0
        {% elsif second = 65 %}
          {{ second }}
        {% end %}
      end
      CRYSTAL
    definition = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::MacroDefNode)
    body = program.arena[definition.body].as(Adamas::Compiler::Frontend::MacroLiteralNode)
    controls = body.pieces.select { |piece| piece.control_keyword == "if" || piece.control_keyword == "elsif" }
    controls.size.should eq(2)
    controls.each do |piece|
      program.arena[piece.expr.not_nil!].should be_a(Adamas::Compiler::Frontend::AssignNode)
    end
  end

  it "preserves an unparenthesized assignment in a macro-if elsif branch" do
    program = macro_assignment_program(<<-CRYSTAL)
      {% if false %}
        0
      {% elsif assigned = false || 65 %}
        {{ assigned }}
      {% end %}
      CRYSTAL
    branch = program.arena[program.roots.first].as(Adamas::Compiler::Frontend::MacroIfNode)
    elsif_branch = program.arena[branch.else_body.not_nil!].as(Adamas::Compiler::Frontend::MacroIfNode)
    assignment = program.arena[elsif_branch.condition].as(Adamas::Compiler::Frontend::AssignNode)
    rhs = program.arena[assignment.value].as(Adamas::Compiler::Frontend::BinaryNode)
    String.new(rhs.operator).should eq("||")
  end

  it "reports malformed assignments and missing right-hand sides in macro conditions" do
    [
      "{% if assigned = %}1{% end %}",
      "{% if = 65 %}1{% end %}",
      "macro assignment_probe\n{% if false %}0{% elsif assigned = %}1{% end %}\nend",
    ].each do |source|
      parser = Adamas::Compiler::Frontend::Parser.new(
        Adamas::Compiler::Frontend::Lexer.new(source), recovery_mode: false)
      parser.parse_program
      parser.diagnostics.should_not be_empty
    end
  end

  it "returns the exact RHS value and retains the variable binding" do
    incoming = Adamas::Compiler::Semantic::MacroArrayValue.new([
      Adamas::Compiler::Semantic::MacroNumberValue.new(65_i64).as(Adamas::Compiler::Semantic::MacroValue),
    ])
    variables = {"incoming" => incoming.as(Adamas::Compiler::Semantic::MacroValue)}
    value = macro_assignment_value("assigned = incoming", variables)
    value.same?(incoming).should be_true
    variables["assigned"].same?(incoming).should be_true
  end

  it "retains false and nil while returning their falsy condition values" do
    {"false" => false, "nil" => false, "0" => true, "\"\"" => true}.each do |literal, truthy|
      program = macro_assignment_program("assigned = #{literal}")
      variables = {} of String => Adamas::Compiler::Semantic::MacroValue
      expander = Adamas::Compiler::Semantic::MacroExpander.new(program, program.arena)
      expander.evaluate_condition_truthiness(program.roots.first, variables: variables).should eq(truthy)
      variables.has_key?("assigned").should be_true
      variables["assigned"].to_macro_output.should eq(literal)
      variables["assigned"].truthy?.should eq(truthy)
    end
  end

  it "evaluates a nested assignment RHS exactly once" do
    variables = {
      "count" => Adamas::Compiler::Semantic::MacroNumberValue.new(0_i64).as(Adamas::Compiler::Semantic::MacroValue),
    }
    value = macro_assignment_value("outer = (inner = (count = count + 1))", variables)
    value.to_macro_output.should eq("1")
    %w(count inner outer).each do |name|
      variables[name].same?(value).should be_true
    end
  end

  it "does not evaluate assignments on short-circuited operands" do
    variables = {} of String => Adamas::Compiler::Semantic::MacroValue
    macro_assignment_value("(left = false) && (right = 65)", variables).to_macro_output.should eq("false")
    variables["left"].to_macro_output.should eq("false")
    variables.has_key?("right").should be_false

    variables.clear
    macro_assignment_value("(left = 65) || (right = 66)", variables).to_macro_output.should eq("65")
    variables["left"].to_macro_output.should eq("65")
    variables.has_key?("right").should be_false
  end

  it "retains assignments from the evaluated operands of boolean expressions" do
    variables = {} of String => Adamas::Compiler::Semantic::MacroValue
    macro_assignment_value("(left = nil) || (right = 65)", variables).to_macro_output.should eq("65")
    variables["left"].to_macro_output.should eq("nil")
    variables["right"].to_macro_output.should eq("65")

    variables.clear
    macro_assignment_value("(left = 65) && (right = false)", variables).to_macro_output.should eq("false")
    variables["left"].to_macro_output.should eq("65")
    variables["right"].to_macro_output.should eq("false")
  end

  it "makes parenthesized falsy condition bindings visible in else and later pieces" do
    variables = {} of String => Adamas::Compiler::Semantic::MacroValue
    output = macro_assignment_body(<<-CRYSTAL, variables)
      {% if (assigned = false) %}
        0
      {% else %}
        {{ assigned == false }}
      {% end %}
      {{ assigned }}
      {% if (assigned = nil) %}
        0
      {% else %}
        {{ assigned.nil? }}
      {% end %}
      {{ assigned }}
      CRYSTAL
    output.should eq("true false true nil")
    variables["assigned"].to_macro_output.should eq("nil")
  end

  it "keeps assignment statements silent while sharing their value semantics" do
    variables = {} of String => Adamas::Compiler::Semantic::MacroValue
    output = macro_assignment_body(<<-CRYSTAL, variables)
      {% assigned = (inner = 65) %}
      {{ assigned }}
      {{ inner }}
      CRYSTAL
    output.should eq("65 65")
  end
end
