require "spec"
require "file_utils"
require "./support/server_helper"

describe "LSP semantic token disk cache" do
  around_each do |example|
    old_xdg = ENV["XDG_CACHE_HOME"]?
    cache_dir = File.join(Dir.tempdir, "cv2_semantic_token_cache_spec_#{Random::Secure.hex(6)}")
    ENV["XDG_CACHE_HOME"] = cache_dir
    begin
      example.run
    ensure
      if old_xdg
        ENV["XDG_CACHE_HOME"] = old_xdg
      else
        ENV.delete("XDG_CACHE_HOME")
      end
      FileUtils.rm_rf(cache_dir) if Dir.exists?(cache_dir)
    end
  end

  it "serves exact disk-backed semantic token cache hits" do
    dir = File.join(Dir.tempdir, "cv2_semantic_token_doc_#{Random::Secure.hex(6)}")
    Dir.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    source = "value = 1\n" * 7000
    File.write(path, source)

    info = File.info(path)
    cached_json = %({"data":[]})
    CrystalV2::Compiler::LSP::SemanticTokenDiskCache.save(path, info.modification_time.to_unix_ns.to_i64, info.size.to_u64, cached_json)

    server = CrystalV2::Compiler::LSP::Server.new(IO::Memory.new, IO::Memory.new, CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false))
    uri = server.spec_did_open_document(source, path)
    response = server.spec_semantic_tokens(uri)

    response["result"]["data"].as_a.should be_empty
  ensure
    FileUtils.rm_rf(dir) if dir && Dir.exists?(dir)
  end

  it "ignores disk cache when the open text differs from the file" do
    dir = File.join(Dir.tempdir, "cv2_semantic_token_doc_#{Random::Secure.hex(6)}")
    Dir.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    disk_source = "value = 1\n" * 7000
    open_source = "value = 2\n" * 7000
    File.write(path, disk_source)

    info = File.info(path)
    cached_json = %({"data":[]})
    CrystalV2::Compiler::LSP::SemanticTokenDiskCache.save(path, info.modification_time.to_unix_ns.to_i64, info.size.to_u64, cached_json)

    server = CrystalV2::Compiler::LSP::Server.new(IO::Memory.new, IO::Memory.new, CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false))
    uri = server.spec_did_open_document(open_source, path)
    response = server.spec_semantic_tokens(uri)

    response["result"]["data"].as_a.should_not be_empty
  ensure
    FileUtils.rm_rf(dir) if dir && Dir.exists?(dir)
  end

  it "returns an empty semantic token delta for the current result id" do
    dir = File.join(Dir.tempdir, "cv2_semantic_token_doc_#{Random::Secure.hex(6)}")
    Dir.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    source = "value = 1\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(IO::Memory.new, IO::Memory.new, CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false))
    uri = server.spec_did_open_document(source, path)
    full_response = server.spec_semantic_tokens(uri)
    result_id = full_response["result"]["resultId"].as_s

    delta_response = server.spec_semantic_tokens_delta(uri, result_id)
    delta_response["result"]["resultId"].as_s.should eq(result_id)
    delta_response["result"]["edits"].as_a.should be_empty
  ensure
    FileUtils.rm_rf(dir) if dir && Dir.exists?(dir)
  end

  it "falls back to full semantic tokens for a stale result id" do
    dir = File.join(Dir.tempdir, "cv2_semantic_token_doc_#{Random::Secure.hex(6)}")
    Dir.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    source = "value = 1\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(IO::Memory.new, IO::Memory.new, CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false))
    uri = server.spec_did_open_document(source, path)
    delta_response = server.spec_semantic_tokens_delta(uri, "stale")

    delta_response["result"]["data"].as_a.should_not be_empty
    delta_response["result"]["resultId"].as_s.should_not eq("stale")
  ensure
    FileUtils.rm_rf(dir) if dir && Dir.exists?(dir)
  end

  it "preserves semantic token result ids across exact close and reopen" do
    dir = File.join(Dir.tempdir, "cv2_semantic_token_doc_#{Random::Secure.hex(6)}")
    Dir.mkdir_p(dir)
    path = File.join(dir, "sample.cr")
    source = "value = 1\n"
    File.write(path, source)

    server = CrystalV2::Compiler::LSP::Server.new(IO::Memory.new, IO::Memory.new, CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false))
    uri = server.spec_did_open_document(source, path)
    full_response = server.spec_semantic_tokens(uri)
    result_id = full_response["result"]["resultId"].as_s

    server.spec_did_close(uri)
    reopened_uri = server.spec_did_open_document(source, path)
    reopened_uri.should eq(uri)
    delta_response = server.spec_semantic_tokens_delta(uri, result_id)

    delta_response["result"]["resultId"].as_s.should eq(result_id)
    delta_response["result"]["edits"].as_a.should be_empty
  ensure
    FileUtils.rm_rf(dir) if dir && Dir.exists?(dir)
  end
end
