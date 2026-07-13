require "spec"
require "../spec_helper"
require "../../src/compiler/cli"

AS_QUESTION_TRY_SOURCE = File.expand_path("../../regression_tests/as_question_try_probe.cr", __DIR__)
AS_QUESTION_TRY_RUN_SAFE = File.expand_path("../../scripts/run_safe.sh", __DIR__)

private def compile_and_run_as_question_try : String
  stem = File.join(Dir.tempdir, "adamas_as_question_try_spec_#{Process.pid}")
  artifacts = [stem, "#{stem}.hir", "#{stem}.ll", "#{stem}.ll.opt.ll", "#{stem}.o", "#{stem}.dwarf"]
  begin
    out_io = IO::Memory.new
    err_io = IO::Memory.new
    status = Adamas::Compiler::CLI.new([
      AS_QUESTION_TRY_SOURCE,
      "-o", stem,
    ]).run(out_io: out_io, err_io: err_io)
    raise "as? try probe compile failed (#{status}): #{err_io}" unless status == 0

    stdout = IO::Memory.new
    stderr = IO::Memory.new
    run_status = Process.run(
      AS_QUESTION_TRY_RUN_SAFE,
      [stem, "15", "2048"],
      output: stdout,
      error: stderr,
    )
    raise "as? try probe runtime failed (#{run_status}): #{stderr}" unless run_status.success?
    wrapped_output = stdout.to_s
    stdout_start = wrapped_output.index("=== STDOUT ===\n")
    stderr_start = wrapped_output.index("=== STDERR ===", stdout_start ? stdout_start.not_nil! : 0)
    if stdout_start && stderr_start
      body_start = stdout_start.not_nil! + "=== STDOUT ===\n".bytesize
      wrapped_output[body_start, stderr_start.not_nil! - body_start]
    else
      wrapped_output
    end
  ensure
    artifacts.each { |path| File.delete(path) if File.exists?(path) }
  end
end

describe "as? result try inline" do
  it "guards a null selected pointer before invoking the block" do
    compile_and_run_as_question_try.should eq("true\ntrue\n")
  end
end
