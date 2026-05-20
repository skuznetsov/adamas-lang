require "spec"
require "file_utils"
require "random/secure"

require "./support/server_helper"

describe CrystalV2::Compiler::LSP::Server do
  around_each do |example|
    prev = ENV["CRYSTALV2_LSP_FORCE_STUB"]?
    ENV["CRYSTALV2_LSP_FORCE_STUB"] = "1"
    begin
      example.run
    ensure
      if prev
        ENV["CRYSTALV2_LSP_FORCE_STUB"] = prev
      else
        ENV.delete("CRYSTALV2_LSP_FORCE_STUB")
      end
    end
  end

  it "reuses formatting responses for unchanged document versions" do
    dir = File.join(Dir.tempdir, "lsp_format_cache_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "main.cr")
    source = "x=1\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false)
    )
    uri = server.spec_store_document(source, dir, path)

    first = server.spec_formatting(uri)
    first["result"].as_a.size.should eq(1)
    server.spec_formatting_cache_version(uri).should eq(1)

    second = server.spec_formatting(uri)
    second.to_json.should eq(first.to_json)
    server.spec_formatting_cache_version(uri).should eq(1)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "invalidates cached formatting when document text changes" do
    dir = File.join(Dir.tempdir, "lsp_format_cache_invalidate_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "main.cr")
    source = "x=1\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false)
    )
    uri = server.spec_store_document(source, dir, path)

    server.spec_formatting(uri)
    server.spec_formatting_cache_version(uri).should eq(1)

    updated = "x = 1\n"
    changes = %([{"text":#{updated.to_json}}])
    server.spec_did_change(uri, 2, changes)
    server.spec_formatting_cache_version(uri).should be_nil

    server.spec_formatting(uri)
    server.spec_formatting_cache_version(uri).should eq(2)
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
