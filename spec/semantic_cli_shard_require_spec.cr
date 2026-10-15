require "./semantic_cli_helpers"

module Adamas::Compiler
  class CLI
    def resolve_shard_require_for_spec(path : String, base_dir : String)
      resolve_require_path(path, base_dir, base_dir)
    end

    def scan_shard_require_for_spec(source : String, base_dir : String)
      parser = Frontend::Parser.new(Frontend::Lexer.new(source))
      program = parser.parse_program
      paths = [] of String
      options = Options.new
      program.roots.each do |root|
        process_require_node(program.arena.as(Frontend::AstArena), root, source, base_dir, base_dir, options, IO::Memory.new, paths)
      end
      paths
    end
  end
end

private def with_shard_require_project(&)
  root = File.join(Dir.tempdir, "shard_require_#{Random::Secure.hex(6)}")
  first = File.join(root, "first")
  second = File.join(root, "second")
  project = File.join(root, "project")
  [first, second, project].each { |path| Dir.mkdir_p(path) }
  previous = ENV["CRYSTAL_PATH"]?
  ENV["CRYSTAL_PATH"] = "#{first}:#{second}"
  begin
    yield root, first, second, project, Adamas::Compiler::CLI.new([] of String)
  ensure
    if previous
      ENV["CRYSTAL_PATH"] = previous
    else
      ENV.delete("CRYSTAL_PATH")
    end
    FileUtils.rm_rf(root)
  end
end

private def write_require_fixture(path : String)
  Dir.mkdir_p(File.dirname(path))
  File.write(path, "# require resolver fixture\n")
  path
end

describe "Crystal require search path and shard layouts" do
  it "searches every CRYSTAL_PATH entry in order" do
    with_shard_require_project do |_, first, second, project, cli|
      later = write_require_fixture(File.join(second, "transport.cr"))
      cli.resolve_shard_require_for_spec("transport", project).should eq(later)
      earlier = write_require_fixture(File.join(first, "transport.cr"))
      cli.resolve_shard_require_for_spec("transport", project).should eq(earlier)
    end
  end

  it "loads a shard entry point from shard/src/shard.cr" do
    with_shard_require_project do |_, _, second, project, cli|
      target = write_require_fixture(File.join(second, "transport/src/transport.cr"))
      cli.resolve_shard_require_for_spec("transport", project).should eq(target)
      cli.resolve_shard_require_for_spec("transport.cr", project).should be_nil
    end
  end

  it "checks flat shard subpaths before namespaced shard subpaths" do
    with_shard_require_project do |_, _, second, project, cli|
      namespaced = write_require_fixture(File.join(second, "transport/src/transport/channel.cr"))
      cli.resolve_shard_require_for_spec("transport/channel", project).should eq(namespaced)
      flat = write_require_fixture(File.join(second, "transport/src/channel.cr"))
      cli.resolve_shard_require_for_spec("transport/channel", project).should eq(flat)
      cli.resolve_shard_require_for_spec("transport/channel.cr", project).should eq(flat)
    end
  end

  it "loads nested shard entry points in both supported layouts" do
    with_shard_require_project do |_, _, second, project, cli|
      namespaced = write_require_fixture(File.join(second, "transport/src/transport/channel/channel.cr"))
      cli.resolve_shard_require_for_spec("transport/channel", project).should eq(namespaced)
      flat = write_require_fixture(File.join(second, "transport/src/channel/channel.cr"))
      cli.resolve_shard_require_for_spec("transport/channel", project).should eq(flat)
    end
  end

  it "does not treat an unqualified require as relative to the current file" do
    with_shard_require_project do |_, _, second, project, cli|
      write_require_fixture(File.join(project, "transport.cr"))
      target = write_require_fixture(File.join(second, "transport.cr"))
      cli.resolve_shard_require_for_spec("transport", project).should eq(target)
    end
  end

  it "keeps relative requires local and accepts an explicit extension" do
    with_shard_require_project do |_, _, second, project, cli|
      write_require_fixture(File.join(second, "transport.cr"))
      target = write_require_fixture(File.join(project, "transport.cr"))
      cli.resolve_shard_require_for_spec("./transport", project).should eq(target)
      cli.resolve_shard_require_for_spec("./transport.cr", project).should eq(target)
      cli.resolve_shard_require_for_spec("./missing", project).should be_nil
    end
  end

  it "loads a wildcard from a later search path entry" do
    with_shard_require_project do |_, _, second, project, cli|
      direct = write_require_fixture(File.join(second, "parts/a.cr"))
      nested = write_require_fixture(File.join(second, "parts/nested/b.cr"))
      cli.resolve_shard_require_for_spec("parts/*", project).should eq([direct])
      cli.resolve_shard_require_for_spec("parts/**", project).should eq([direct, nested])
    end
  end

  it "follows a symlinked directory during recursive wildcard loading" do
    with_shard_require_project do |root, _, second, project, cli|
      target = write_require_fixture(File.join(root, "external/b.cr"))
      Dir.mkdir_p(File.join(second, "parts"))
      File.symlink(File.dirname(target), File.join(second, "parts/linked"))
      cli.resolve_shard_require_for_spec("parts/**", project).should eq([File.join(second, "parts/linked/b.cr")])
    end
  end

  it "accepts an existing empty wildcard directory" do
    with_shard_require_project do |_, _, second, project, cli|
      Dir.mkdir_p(File.join(second, "empty"))
      cli.resolve_shard_require_for_spec("empty/*", project).should eq([] of String)
    end
  end

  it "rejects a missing active require instead of continuing with missing definitions" do
    with_shard_require_project do |_, _, _, project, cli|
      expect_raises(Adamas::HIR::LoweringError, /can't find.*missing_transport/) do
        cli.scan_shard_require_for_spec("require \"missing_transport\"", project)
      end
    end
  end

  it "does not resolve a require from an inactive macro branch" do
    with_shard_require_project do |_, _, _, project, cli|
      cli.scan_shard_require_for_spec("{% if false %}\nrequire \"missing_transport\"\n{% end %}", project).should be_empty
    end
  end
end
