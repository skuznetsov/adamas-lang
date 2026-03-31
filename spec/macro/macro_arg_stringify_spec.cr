require "spec"

require "../../src/compiler/semantic/analyzer"

describe "Macro argument stringification" do
  it "preserves call and member access expressions in macro arguments" do
    source = <<-CR
      module Intrinsics
        macro memset(dest, val, len, is_volatile)
          ::LibIntrinsics.memset({{dest}}, {{val}}, {{len}}, {{is_volatile}})
        end
      end

      Intrinsics.memset(foo.as(Void*), 0_u8, bytesize(count), false)
    CR

    lexer = CrystalV2::Compiler::Frontend::Lexer.new(source)
    parser = CrystalV2::Compiler::Frontend::Parser.new(lexer)
    program = parser.parse_program

    analyzer = CrystalV2::Compiler::Semantic::Analyzer.new(program)
    analyzer.collect_symbols

    analyzer.semantic_diagnostics.should be_empty
    analyzer.generated_overlay.top_level_roots.size.should eq(1)

    root = analyzer.generated_overlay.top_level_roots.first
    program.arena[root].should be_a(CrystalV2::Compiler::Frontend::CallNode)
    analyzer.generated_overlay.generated_source_for(root).should eq("::LibIntrinsics.memset(foo.as(Void*), 0_u8, bytesize(count), false)\n")
  end
end
