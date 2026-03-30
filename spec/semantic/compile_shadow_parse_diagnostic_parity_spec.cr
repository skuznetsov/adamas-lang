require "spec"

require "../../src/compiler/frontend/ast"
require "../../src/compiler/frontend/parser/diagnostic"
require "../../src/compiler/semantic/compile_shadow_parse_diagnostic_parity"

describe CrystalV2::Compiler::Semantic::CompileShadowParseDiagnosticParity do
  it "counts missing and extra parse diagnostics by signature" do
    compile_diagnostics = [
      CrystalV2::Compiler::Frontend::Diagnostic.new(
        "unexpected RParen",
        CrystalV2::Compiler::Frontend::Span.new(0, 0, 1, 1, 1, 1),
        file_path: "main.cr",
      ),
      CrystalV2::Compiler::Frontend::Diagnostic.new(
        "unexpected RParen",
        CrystalV2::Compiler::Frontend::Span.new(0, 0, 1, 1, 1, 1),
        file_path: "main.cr",
      ),
    ]
    shadow_diagnostics = [
      CrystalV2::Compiler::Frontend::Diagnostic.new(
        "unexpected RParen",
        CrystalV2::Compiler::Frontend::Span.new(0, 0, 1, 1, 1, 1),
        file_path: "main.cr",
      ),
      CrystalV2::Compiler::Frontend::Diagnostic.new(
        "unexpected token",
        CrystalV2::Compiler::Frontend::Span.new(2, 4, 2, 1, 2, 3),
        file_path: "main.cr",
      ),
    ]

    parity = CrystalV2::Compiler::Semantic::CompileShadowParseDiagnosticParity.compare(
      compile_diagnostics,
      shadow_diagnostics
    )

    parity.compile_total.should eq(2)
    parity.compile_unique_count.should eq(1)
    parity.shadow_total.should eq(2)
    parity.shadow_unique_count.should eq(2)
    parity.gap_count.should eq(2)
    parity.missing_in_shadow.should eq(["main.cr:1:1-1:1 unexpected RParen"])
    parity.extra_in_shadow.should eq(["main.cr:2:1-2:3 unexpected token"])
  end
end
