require "spec"
require "file_utils"
require "random/secure"

require "./support/server_helper"

describe "LSP AST cache dependency loading" do
  around_each do |example|
    prev_stub = ENV["CRYSTALV2_LSP_FORCE_STUB"]?
    prev_ast_cache = ENV["LSP_AST_CACHE"]?
    ENV["CRYSTALV2_LSP_FORCE_STUB"] = "1"
    ENV["LSP_AST_CACHE"] = "1"
    begin
      example.run
    ensure
      if prev_stub
        ENV["CRYSTALV2_LSP_FORCE_STUB"] = prev_stub
      else
        ENV.delete("CRYSTALV2_LSP_FORCE_STUB")
      end

      if prev_ast_cache
        ENV["LSP_AST_CACHE"] = prev_ast_cache
      else
        ENV.delete("LSP_AST_CACHE")
      end
    end
  end

  it "reuses dependency AST cache on a second server instance" do
    base_dir = File.join(Dir.tempdir, "lsp_ast_dep_#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(base_dir)

    helper_path = File.join(base_dir, "helper.cr")
    main_path = File.join(base_dir, "main.cr")
    log1 = File.join(base_dir, "server1.log")
    log2 = File.join(base_dir, "server2.log")
    cache_path = Adamas::Compiler::LSP::AstCache.cache_path(helper_path)

    File.write(helper_path, <<-CR)
    module Dep
      class Helper
        def value
          42
        end
      end
    end
    CR

    main_source = <<-CR
    require "./helper"

    module Entry
      def self.run
        Dep::Helper.new.value
      end
    end
    CR
    File.write(main_path, main_source)

    server1 = Adamas::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      Adamas::Compiler::LSP::ServerConfig.new(
        background_indexing: false,
        project_cache: false,
        ast_cache: true,
        debug_log_path: log1
      )
    )
    uri1 = server1.spec_store_document(main_source, base_dir, main_path)

    helper_offset = main_source.index("Helper.new").not_nil!
    helper_line = main_source[0, helper_offset].count('\n')
    helper_char = helper_offset - (main_source.rindex('\n', helper_offset) || -1) - 1
    definition1 = server1.spec_definition(uri1, helper_line, helper_char)
    location1 = definition1["result"].as_a.first
    location1["uri"].as_s.should contain("helper.cr")
    File.exists?(cache_path).should be_true

    server2 = Adamas::Compiler::LSP::Server.new(
      IO::Memory.new,
      IO::Memory.new,
      Adamas::Compiler::LSP::ServerConfig.new(
        background_indexing: false,
        project_cache: false,
        ast_cache: true,
        debug_log_path: log2
      )
    )
    uri2 = server2.spec_store_document(main_source, base_dir, main_path)

    definition2 = server2.spec_definition(uri2, helper_line, helper_char)
    location2 = definition2["result"].as_a.first
    location2["uri"].as_s.should contain("helper.cr")

    File.read(log2).should contain("Loading dependency #{helper_path} from AST cache")
  ensure
    FileUtils.rm_rf(base_dir) if base_dir
    File.delete(cache_path) if cache_path && File.exists?(cache_path)
  end
end
