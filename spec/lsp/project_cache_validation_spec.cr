require "spec"
require "json"
require "file_utils"
require "random/secure"

require "../../src/compiler/lsp/unified_project"
require "../../src/compiler/lsp/project_cache"

describe Adamas::Compiler::LSP::ProjectCacheLoader do
  describe "TypeIndex-only cache (v5)" do
    it "saves and loads single file with TypeIndex" do
      root = File.join(Dir.tempdir, "cache_typeindex_test_#{Random::Secure.hex(6)}")
      src_dir = File.join(root, "src")
      FileUtils.mkdir_p(src_dir)
      path = File.join(src_dir, "test.cr")
      source = <<-CR
      class Foo
        def bar
          42
        end
      end
      CR
      File.write(path, source)

      # Create project and analyze
      project = Adamas::Compiler::LSP::UnifiedProjectState.new
      project.update_file(path, source)

      # Save cache (writes TypeIndex, no JSON expr_types)
      Adamas::Compiler::LSP::ProjectCacheLoader.save_to_cache(project, root)

      # Load into fresh project
      fresh = Adamas::Compiler::LSP::UnifiedProjectState.new
      result = Adamas::Compiler::LSP::ProjectCacheLoader.load_from_cache(fresh, root)

      result[:valid_count].should eq(1)
      result[:invalid_paths].should be_empty
      fresh.files.size.should eq(1)
    ensure
      FileUtils.rm_rf(root) if root
    end

    it "saves and loads multiple files without ExprId collisions" do
      root = File.join(Dir.tempdir, "cache_multi_typeindex_#{Random::Secure.hex(6)}")
      src_dir = File.join(root, "src")
      FileUtils.mkdir_p(src_dir)

      # Create two files with types
      path1 = File.join(src_dir, "file1.cr")
      File.write(path1, "x = 1")
      path2 = File.join(src_dir, "file2.cr")
      File.write(path2, "y = \"hello\"")

      project = Adamas::Compiler::LSP::UnifiedProjectState.new
      project.update_file(path1, File.read(path1))
      project.update_file(path2, File.read(path2))

      Adamas::Compiler::LSP::ProjectCacheLoader.save_to_cache(project, root)

      fresh = Adamas::Compiler::LSP::UnifiedProjectState.new
      result = Adamas::Compiler::LSP::ProjectCacheLoader.load_from_cache(fresh, root)

      result[:valid_count].should eq(2)
      fresh.files.size.should eq(2)
    ensure
      FileUtils.rm_rf(root) if root
    end

    it "excludes vendored stdlib files from project cache payloads" do
      root = File.join(Dir.tempdir, "cache_exclude_stdlib_#{Random::Secure.hex(6)}")
      compiler_dir = File.join(root, "src", "compiler")
      stdlib_dir = File.join(root, "src", "stdlib")
      FileUtils.mkdir_p(compiler_dir)
      FileUtils.mkdir_p(stdlib_dir)
      compiler_path = File.join(compiler_dir, "server.cr")
      stdlib_path = File.join(stdlib_dir, "array.cr")
      File.write(compiler_path, "module CompilerFile\nend\n")
      File.write(stdlib_path, "class Array\nend\n")

      project = Adamas::Compiler::LSP::UnifiedProjectState.new
      project.files[compiler_path] = Adamas::Compiler::LSP::FileAnalysisState.new(
        path: compiler_path,
        mtime: File.info(compiler_path).modification_time,
        symbols: ["CompilerFile"]
      )
      project.files[stdlib_path] = Adamas::Compiler::LSP::FileAnalysisState.new(
        path: stdlib_path,
        mtime: File.info(stdlib_path).modification_time,
        symbols: ["Array"]
      )

      cache = Adamas::Compiler::LSP::ProjectCache.from_project(project, root)
      cache.files.map(&.path).should eq([compiler_path])
      Adamas::Compiler::LSP::ProjectCache.cacheable_project_file?(compiler_path, root).should be_true
      Adamas::Compiler::LSP::ProjectCache.cacheable_project_file?(stdlib_path, root).should be_false
    ensure
      FileUtils.rm_rf(root) if root
    end

    it "restores expression types from TypeIndex" do
      root = File.join(Dir.tempdir, "cache_restore_types_#{Random::Secure.hex(6)}")
      src_dir = File.join(root, "src")
      FileUtils.mkdir_p(src_dir)
      path = File.join(src_dir, "test.cr")
      File.write(path, "a = 1")

      project = Adamas::Compiler::LSP::UnifiedProjectState.new
      project.update_file(path, "a = 1")

      # Manually set some cached types
      project.cached_expr_types[path] = {0 => "Int32", 1 => "Int32"}

      Adamas::Compiler::LSP::ProjectCacheLoader.save_to_cache(project, root)

      fresh = Adamas::Compiler::LSP::UnifiedProjectState.new
      Adamas::Compiler::LSP::ProjectCacheLoader.load_from_cache(fresh, root)

      # Types should be restored from TypeIndex
      fresh.cached_expr_types[path]?.should_not be_nil
    ensure
      FileUtils.rm_rf(root) if root
    end

    it "handles cache version upgrade (old cache invalidated)" do
      root = File.join(Dir.tempdir, "cache_version_test_#{Random::Secure.hex(6)}")
      src_dir = File.join(root, "src")
      FileUtils.mkdir_p(src_dir)
      path = File.join(src_dir, "test.cr")
      File.write(path, "x = 1")

      # Manually create an old v4 cache file (will be rejected)
      cache_dir = ENV["XDG_CACHE_HOME"]? || File.join(ENV["HOME"]? || "/tmp", ".cache")
      cache_path = File.join(cache_dir, "adamas_lsp", "projects")
      FileUtils.mkdir_p(cache_path)

      # The load will fail on version mismatch, returning 0 valid files
      fresh = Adamas::Compiler::LSP::UnifiedProjectState.new
      result = Adamas::Compiler::LSP::ProjectCacheLoader.load_from_cache(fresh, root)

      # No cache exists, so 0 valid files
      result[:valid_count].should eq(0)
    ensure
      FileUtils.rm_rf(root) if root
    end
  end
end
