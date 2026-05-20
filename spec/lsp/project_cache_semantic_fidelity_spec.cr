require "spec"
require "file_utils"
require "random/secure"

require "./support/server_helper"
require "../../src/compiler/lsp/project_cache"

private def lsp_line_char(source : String, needle : String, occurrence : Int32 = 0, at_end : Bool = false) : {Int32, Int32}
  offset = nil
  search_from = 0
  (occurrence + 1).times do
    found = source.index(needle, search_from)
    raise "Missing needle #{needle}" unless found
    offset = found
    search_from = found + needle.bytesize
  end

  target = offset.not_nil! + (at_end ? needle.bytesize : 0)
  line = source[0, target].count('\n')
  line_start = source.rindex('\n', target) || -1
  {line, target - line_start - 1}
end

private def with_lsp_project_cache_env(&)
  prev_stub = ENV["CRYSTALV2_LSP_FORCE_STUB"]?
  prev_xdg = ENV["XDG_CACHE_HOME"]?
  cache_dir = File.join(Dir.tempdir, "lsp_project_cache_env_#{Random::Secure.hex(6)}")
  FileUtils.mkdir_p(cache_dir)
  ENV["CRYSTALV2_LSP_FORCE_STUB"] = "1"
  ENV["XDG_CACHE_HOME"] = cache_dir
  yield
ensure
  if prev_stub
    ENV["CRYSTALV2_LSP_FORCE_STUB"] = prev_stub
  else
    ENV.delete("CRYSTALV2_LSP_FORCE_STUB")
  end

  if prev_xdg
    ENV["XDG_CACHE_HOME"] = prev_xdg
  else
    ENV.delete("XDG_CACHE_HOME")
  end

  FileUtils.rm_rf(cache_dir) if cache_dir
end

describe "LSP project cache semantic fidelity" do
  it "preserves cached method parameter metadata for signature help" do
    with_lsp_project_cache_env do
      root = File.join(Dir.tempdir, "lsp_project_cache_sig_#{Random::Secure.hex(6)}")
      src_dir = File.join(root, "src")
      FileUtils.mkdir_p(src_dir)
      File.write(File.join(root, "shard.yml"), "name: lsp_project_cache_sig\n")

      helper_path = File.join(src_dir, "helper.cr")
      helper_source = <<-CR
      class Helper
        def value(scale : Int32) : Int32
          scale
        end
      end
      CR
      File.write(helper_path, helper_source)

      main_path = File.join(src_dir, "main.cr")
      main_source = <<-CR
      require "./helper"

      helper = Helper.new
      helper.value(2)
      CR
      File.write(main_path, main_source)

      baseline = CrystalV2::Compiler::LSP::Server.new(
        IO::Memory.new,
        IO::Memory.new,
        CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: false)
      )
      baseline_uri = baseline.spec_store_document(main_source, src_dir, main_path)
      sig_line, sig_char = lsp_line_char(main_source, "value(", at_end: true)
      baseline_sig = baseline.spec_signature_help(baseline_uri, sig_line, sig_char)
      baseline_label = baseline_sig["result"]["signatures"].as_a.first["label"].as_s
      baseline_label.should contain("scale : Int32")
      completion_line, completion_char = lsp_line_char(main_source, "helper.", at_end: true)
      baseline_completion = baseline.spec_completion(baseline_uri, completion_line, completion_char)
      baseline_labels = baseline_completion["result"].as_a.map { |item| item["label"].as_s }
      baseline_labels.should contain("value")
      definition_line, definition_char = lsp_line_char(main_source, "value", occurrence: 0)
      baseline_definition = baseline.spec_definition(baseline_uri, definition_line, definition_char)
      baseline_definition["result"].as_a.first["uri"].as_s.should contain("helper.cr")

      project = CrystalV2::Compiler::LSP::UnifiedProjectState.new
      project.update_file(helper_path, helper_source)
      project.update_file(main_path, main_source)
      CrystalV2::Compiler::LSP::ProjectCacheLoader.save_to_cache(project, root)

      cached = CrystalV2::Compiler::LSP::Server.new(
        IO::Memory.new,
        IO::Memory.new,
        CrystalV2::Compiler::LSP::ServerConfig.new(background_indexing: false, project_cache: true)
      )
      cached_uri = cached.spec_did_open_document(main_source, main_path)
      cached_sig = cached.spec_signature_help(cached_uri, sig_line, sig_char)
      cached_label = cached_sig["result"]["signatures"].as_a.first["label"].as_s

      cached_label.should eq(baseline_label)
      cached_completion = cached.spec_completion(cached_uri, completion_line, completion_char)
      cached_completion["result"].as_a.map { |item| item["label"].as_s }.should contain("value")
      cached_definition = cached.spec_definition(cached_uri, definition_line, definition_char)
      cached_definition["result"].as_a.first["uri"].as_s.should eq(baseline_definition["result"].as_a.first["uri"].as_s)
    ensure
      FileUtils.rm_rf(root) if root
    end
  end
end
