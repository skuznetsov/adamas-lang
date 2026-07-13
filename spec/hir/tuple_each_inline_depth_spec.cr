require "../spec_helper"
require "../../src/compiler/cli"

TUPLE_EACH_PROBE_SOURCE = File.expand_path("../../regression_tests/tuple_each_depth_probe.cr", __DIR__)
TUPLE_EACH_RUN_SAFE = File.expand_path("../../scripts/run_safe.sh", __DIR__)

private def emit_tuple_each_probe_hir(env_overrides : Hash(String, String)) : String
  stem = File.join(Dir.tempdir, "adamas_tuple_each_depth_spec_#{Process.pid}")
  hir_path = "#{stem}.hir"
  previous = {} of String => String?
  env_overrides.each do |key, value|
    previous[key] = ENV[key]?
    ENV[key] = value
  end

  out_io = IO::Memory.new
  err_io = IO::Memory.new
  status = Adamas::Compiler::CLI.new([
    TUPLE_EACH_PROBE_SOURCE,
    "--no-prelude",
    "--emit", "hir",
    "--no-link",
    "-o", stem,
  ]).run(out_io: out_io, err_io: err_io)
  raise "tuple each probe failed (#{status}): #{err_io}" unless status == 0
  raise "tuple each probe did not emit HIR: #{err_io}" unless File.exists?(hir_path)
  File.read(hir_path)
ensure
  previous ||= {} of String => String?
  env_overrides.each_key do |key|
    if value = previous[key]?
      ENV[key] = value
    else
      ENV.delete(key)
    end
  end
  cleanup_stem = stem || ""
  cleanup_hir = hir_path || ""
  [cleanup_stem, cleanup_hir, "#{cleanup_stem}.ll", "#{cleanup_stem}.o"].each do |path|
    File.delete(path) if !path.empty? && File.exists?(path)
  end
end

private def compile_and_run_tuple_each_probe : String
  stem = File.join(Dir.tempdir, "adamas_tuple_each_runtime_spec_#{Process.pid}")
  artifacts = [stem, "#{stem}.hir", "#{stem}.ll", "#{stem}.ll.opt.ll", "#{stem}.o", "#{stem}.dwarf"]
  overrides = {
    "INLINE_YIELD_MAX_DEPTH"      => "0",
    "INLINE_YIELD_MAX_REPEAT"     => "0",
    "INLINE_YIELD_MAX_BLOCK_BODY_DEPTH" => "0",
    "ADAMAS_DISABLE_INLINE_YIELD" => "1",
  }
  previous = {} of String => String?
  overrides.each do |key, value|
    previous[key] = ENV[key]?
    ENV[key] = value
  end

  begin
    out_io = IO::Memory.new
    err_io = IO::Memory.new
    status = Adamas::Compiler::CLI.new([
      TUPLE_EACH_PROBE_SOURCE,
      "--no-prelude",
      "-o", stem,
    ]).run(out_io: out_io, err_io: err_io)
    raise "tuple each runtime probe compile failed (#{status}): #{err_io}" unless status == 0

    stdout = IO::Memory.new
    stderr = IO::Memory.new
    run_status = Process.run(
      TUPLE_EACH_RUN_SAFE,
      [stem, "15", "2048"],
      output: stdout,
      error: stderr,
    )
    raise "tuple each runtime probe failed (#{run_status}): #{stderr}" unless run_status.success?
    "#{stdout}#{stderr}"
  ensure
    overrides.each_key do |key|
      if value = previous[key]?
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
    artifacts.each { |path| File.delete(path) if File.exists?(path) }
  end
end

describe "Tuple#each inline depth" do
  it "keeps the registered concrete Tuple body inlined under every guard" do
    hir = emit_tuple_each_probe_hir({
      "INLINE_YIELD_MAX_DEPTH" => "0",
      "INLINE_YIELD_MAX_REPEAT" => "0",
      "INLINE_YIELD_MAX_BLOCK_BODY_DEPTH" => "0",
      "ADAMAS_DISABLE_INLINE_YIELD" => "1",
    })

    hir.should_not contain("Tuple#each$block")
    hir.should contain("func @tuple_each_nested_probe")
    hir.should contain("func @tuple_empty_probe")
    hir.should contain("func @tuple_each_next_probe")
    hir.should contain("func @tuple_each_heterogeneous_probe")
    hir.should contain("index_get")
    hir.should contain("binop Add")

    hetero_start = hir.index("func @tuple_each_heterogeneous_probe")
    hetero_start.should_not be_nil
    hetero_tail = hir[hetero_start.not_nil!..]
    hetero_end = hetero_tail.index("\nfunc @")
    hetero = hetero_end ? hetero_tail[0, hetero_end] : hetero_tail
    hetero.should_not contain("*Nil")
    hetero.should_not contain("variant -2")
  end

  it "still honors disabled inline yield for a non-Tuple receiver" do
    hir = emit_tuple_each_probe_hir({"ADAMAS_DISABLE_INLINE_YIELD" => "1"})

    hir.should contain("call repeat_once$block")
  end

  it "preserves break semantics across concrete Tuple#each expansion" do
    output = compile_and_run_tuple_each_probe
    output.should match(/(?:^|\n)33(?:\n|$)/)
    output.should match(/(?:^|\n)12(?:\n|$)/)
    output.should match(/(?:^|\n)1212(?:\n|$)/)
    output.should match(/(?:^|\n)123(?:\n|$)/)
  end
end
