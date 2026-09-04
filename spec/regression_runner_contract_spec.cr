require "spec"
require "file_utils"

# Real runners and supervisor, fake compiler: no compiler bootstrap is required
# to establish whether a process result is classified correctly.
private class RegressionRunnerFixture
  getter root : String
  getter work : String

  def initialize
    @root = File.expand_path("..", __DIR__)
    @work = File.join(Dir.tempdir, "adamas_runner_contract_#{Process.pid}_#{Random.rand(1_000_000)}")
    FileUtils.mkdir_p(File.join(@work, "regression_tests/combined"))
    FileUtils.mkdir_p(File.join(@work, "scripts"))
    File.symlink(File.join(@root, "scripts/run_safe.sh"), File.join(@work, "scripts/run_safe.sh"))
    %w[run_all.sh run_combined.sh run_all_suites.sh].each do |name|
      target = File.join(@work, "regression_tests", name)
      FileUtils.cp(File.join(@root, "regression_tests", name), target)
      File.chmod(target, 0o755)
    end
    File.write(File.join(@work, "compiler"), <<-'SH')
      #!/bin/bash
      src=""
      out=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -o|--output) out="$2"; shift ;;
          *.cr) src="$1" ;;
        esac
        shift
      done
      [ -n "$out" ] || out="${src%.cr}"
      name=$(basename "$src" .cr)
      case "$name" in
        compile_fail) echo "intentional compile failure" >&2; exit 3 ;;
        no_binary) exit 0 ;;
      esac
      rc=0
      case "$name" in *_exit7) rc=7 ;; esac
      printf '#!/bin/bash\nprintf "MARKER\n"\n' > "$out"
      case "$name" in
        signal) printf 'kill -TERM $$\n' >> "$out" ;;
        timeout) printf 'exec sleep 60\n' >> "$out" ;;
        *) printf 'exit %s\n' "$rc" >> "$out" ;;
      esac
      chmod +x "$out"
    SH
    File.chmod(File.join(@work, "compiler"), 0o755)
  end

  def add(name : String, combined : Bool = false)
    dir = File.join(@work, combined ? "regression_tests/combined" : "regression_tests")
    marker = name.starts_with?("marker_") || name.in?("signal", "timeout") ? "MARKER" : nil
    marker = "EXPECTED_OTHER" if name == "wrong_marker"
    File.write(File.join(dir, "#{name}.cr"), marker ? "# EXPECT: #{marker}\n" : "# fake compiler fixture\n")
    if name.starts_with?("golden_")
      File.write(File.join(dir, "#{name}.out"), name == "golden_wrong" ? "WRONG\n" : "MARKER\n")
    end
  end

  def run(name : String)
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run(
      File.join(@root, "scripts/run_safe.sh"),
      ["/bin/bash", "60", "512", "regression_tests/#{name}", "./compiler", "1"],
      chdir: @work, output: stdout, error: stderr,
      env: {"RUN_SAFE_PASSTHROUGH_STDIO" => nil, "RUN_SAFE_RESOURCE_FILE" => nil}
    )
    {status.exit_code, "#{stdout}#{stderr}"}
  end

  def cleanup
    FileUtils.rm_rf(@work)
  end
end

describe "regression runner process verdicts" do
  {"run_all.sh" => false, "run_combined.sh" => true}.each do |runner, combined|
    it "rejects nonzero exits before matching output in #{runner}" do
      fixture = RegressionRunnerFixture.new
      begin
        positives = %w[marker_ok unmarked_ok]
        failures = %w[marker_exit7 unmarked_exit7 wrong_marker compile_fail no_binary signal timeout]
        if combined
          positives << "golden_ok"
          failures.concat(%w[golden_exit7 golden_wrong])
        end
        (positives + failures).each { |name| fixture.add(name, combined) }
        rc, output = fixture.run(runner)
        rc.should eq(1), output
        lines = output.lines.map(&.strip)
        positives.each { |name| lines.should contain("PASS: #{name}"), output }
        failures.each do |name|
          lines.any? { |line| line.matches?(/^FAIL \([^)]*\): #{name}(?:\s|$)/) }.should be_true, output
        end
      ensure
        fixture.cleanup
      end
    end
  end

  {false, true}.each do |original_fails|
    {false, true}.each do |combined_fails|
      it "propagates original=#{original_fails}, combined=#{combined_fails} through the aggregate" do
        fixture = RegressionRunnerFixture.new
        begin
          fixture.add(original_fails ? "marker_exit7" : "marker_ok")
          fixture.add(combined_fails ? "golden_exit7" : "golden_ok", true)
          rc, output = fixture.run("run_all_suites.sh")
          rc.should eq(original_fails || combined_fails ? 1 : 0), output
          output.should contain(original_fails || combined_fails ? "SOME TESTS FAILED" : "ALL SUITES PASSED")
        ensure
          fixture.cleanup
        end
      end
    end
  end
end
