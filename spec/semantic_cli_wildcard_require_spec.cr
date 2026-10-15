require "./semantic_cli_helpers"

include SemanticCliSpecHelpers

module Adamas::Compiler
  class CLI
    def resolve_wildcard_for_spec(req_path : String, base_dir : String, stdlib_root : String) : Array(String)?
      previous_stdlib_path = @@stdlib_path
      @@stdlib_path = stdlib_root
      resolve_wildcard_require(req_path, base_dir)
    ensure
      @@stdlib_path = previous_stdlib_path
    end
  end
end

describe Adamas::Compiler::CLI do
  it "resolves relative wildcard requires from the requiring file directory" do
    root = File.join(Dir.tempdir, "relative_wildcard_require_#{Random::Secure.hex(6)}")
    stdlib_root = File.join(root, "search_root")
    project_root = File.join(root, "project")
    nested_dir = File.join(project_root, "nested")
    deep_dir = File.join(nested_dir, "deep")
    entry_path = File.join(nested_dir, "entry.cr")
    sibling_path = File.join(nested_dir, "sibling.cr")
    leaf_path = File.join(deep_dir, "leaf.cr")

    Dir.mkdir_p(stdlib_root)
    Dir.mkdir_p(deep_dir)
    File.write(File.join(stdlib_root, "search_root_decoy.cr"), "class SearchRootDecoy; end\n")
    File.write(File.join(root, "parent_search_root_decoy.cr"), "class ParentSearchRootDecoy; end\n")
    File.write(entry_path, "class RelativeGlobEntry; end\n")
    File.write(sibling_path, "class RelativeGlobSibling; end\n")
    File.write(leaf_path, "class RelativeGlobLeaf; end\n")

    begin
      cli = Adamas::Compiler::CLI.new([] of String)
      direct_expected = [entry_path, sibling_path].map { |path| File.expand_path(path) }.sort
      # Crystal visits sorted files before recursively visiting sorted directories.
      recursive_expected = direct_expected + [File.expand_path(leaf_path)]

      cli.resolve_wildcard_for_spec("./*", nested_dir, stdlib_root).should eq(direct_expected)
      cli.resolve_wildcard_for_spec("./**", nested_dir, stdlib_root).should eq(recursive_expected)
      cli.resolve_wildcard_for_spec("../*", deep_dir, stdlib_root).should eq(direct_expected)
      cli.resolve_wildcard_for_spec("../**", deep_dir, stdlib_root).should eq(recursive_expected)
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
