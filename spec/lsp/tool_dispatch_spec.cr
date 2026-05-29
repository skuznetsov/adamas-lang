require "spec"
require "file_utils"
require "../../src/compiler/lsp/tool_dispatch"

describe Adamas::Compiler::LSP::ToolDispatch do
  it "recognizes crystal tool lsp and preserves child args" do
    args = ["tool", "lsp", "--stdio", "--log=trace"]

    Adamas::Compiler::LSP::ToolDispatch.tool_lsp?(args).should be_true
    Adamas::Compiler::LSP::ToolDispatch.child_args(args).should eq(["--stdio", "--log=trace"])
  end

  it "accepts crystal tools lsp as an alias" do
    args = ["tools", "lsp", "--stdio"]

    Adamas::Compiler::LSP::ToolDispatch.tool_lsp?(args).should be_true
    Adamas::Compiler::LSP::ToolDispatch.child_args(args).should eq(["--stdio"])
  end

  it "does not treat other compiler invocations as LSP tool mode" do
    Adamas::Compiler::LSP::ToolDispatch.tool_lsp?(["src/main.cr"]).should be_false
    Adamas::Compiler::LSP::ToolDispatch.tool_lsp?(["lsp"]).should be_false
    Adamas::Compiler::LSP::ToolDispatch.tool_lsp?(["tool", "format"]).should be_false
  end

  it "prefers explicit LSP server path configuration" do
    Adamas::Compiler::LSP::ToolDispatch
      .resolve_server_path("/tmp/adamas", "/custom/adamas_lsp")
      .should eq("/custom/adamas_lsp")
  end

  it "resolves a sibling adamas_lsp executable" do
    dir = File.join(Dir.tempdir, "cv2_lsp_dispatch_#{Random::Secure.hex(6)}")
    Dir.mkdir_p(dir)
    begin
      compiler_path = File.join(dir, "adamas")
      server_path = File.join(dir, "adamas_lsp")
      File.write(compiler_path, "")
      File.write(server_path, "")

      Adamas::Compiler::LSP::ToolDispatch
        .resolve_server_path(compiler_path)
        .should eq(server_path)
    ensure
      FileUtils.rm_rf(dir) if Dir.exists?(dir)
    end
  end
end
