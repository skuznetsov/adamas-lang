require "spec"

require "../src/compiler/frontend/diagnostic_formatter"

alias Span = Adamas::Compiler::Frontend::Span
alias Diagnostic = Adamas::Compiler::Frontend::Diagnostic
alias DiagnosticFormatter = Adamas::Compiler::Frontend::DiagnosticFormatter

describe DiagnosticFormatter do
  it "formats single line diagnostic with underline" do
    source = "foo + bar"
    span = Span.new(0, 0, 1, 5, 1, 8)
    diagnostic = Diagnostic.new("unexpected identifier", span)

    formatted = DiagnosticFormatter.format(source, diagnostic)
    formatted.should eq("1:5-1:8 unexpected identifier\n  1 | foo + bar\n    |     ^^^")
  end

  it "formats multi-line diagnostic" do
    source = %(line1\nline2\nline3)
    span = Span.new(0, 0, 2, 1, 3, 3)
    diagnostic = Diagnostic.new("multi-line issue", span)

    formatted = DiagnosticFormatter.format(source, diagnostic)
    formatted.should eq("2:1-3:3 multi-line issue\n  2 | line2\n    | ^^^^^\n  3 | line3\n    | ^^^")
  end

  it "falls back to base string when source unavailable" do
    span = Span.new(0, 0, 1, 1, 1, 1)
    diagnostic = Diagnostic.new("missing context", span)

    formatted = DiagnosticFormatter.format(nil, diagnostic)
    formatted.should eq("1:1-1:1 missing context")
  end

  it "formats file-aware diagnostics from a source map" do
    diagnostic = Diagnostic.new(
      "undefined local variable or method 'missing'",
      Span.new(0, 0, 1, 1, 1, 8),
      file_path: "/tmp/main.cr"
    )

    formatted = DiagnosticFormatter.format({"/tmp/main.cr" => "missing\n"}, diagnostic)
    formatted.should eq("/tmp/main.cr:1:1-1:8 undefined local variable or method 'missing'\n  1 | missing\n    | ^^^^^^^")
  end

  it "formats related spans as notes" do
    diagnostic = Diagnostic.new(
      "undefined local variable or method 'missing'",
      Span.new(0, 0, 2, 5, 2, 12),
      file_path: "/tmp/generated.cr",
      related_spans: [
        Adamas::Compiler::Frontend::RelatedSpan.new(
          Span.new(0, 0, 1, 1, 1, 8),
          "expanded from macro call here",
          file_path: "/tmp/main.cr"
        ),
      ]
    )

    formatted = DiagnosticFormatter.format(
      {
        "/tmp/generated.cr" => "  missing + 1\n",
        "/tmp/main.cr"      => "define_bad(:alpha)\n",
      },
      diagnostic
    )

    formatted.should contain("/tmp/generated.cr:2:5-2:12 undefined local variable or method 'missing'")
    formatted.should contain("note: expanded from macro call here")
    formatted.should contain("  --> /tmp/main.cr:1:1-1:8")
    formatted.should contain("define_bad(:alpha)")
  end
end
