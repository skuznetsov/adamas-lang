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
      printf 'generated sibling artifact\n' > "${out}.ll"
      case "$name" in
        compile_fail) echo "intentional compile failure" >&2; exit 3 ;;
        no_binary) exit 0 ;;
        nonexec_compile)
          printf '#!/bin/bash\ntouch partial_executed\n' > "$out"
          exit 0
          ;;
        compile_timeout)
          echo $$ > compiler.pid
          sleep 60 &
          echo $! > compiler_child.pid
          wait
          exit 0
          ;;
        partial_compile)
          printf '#!/bin/bash\ntouch partial_executed\nexit 0\n' > "$out"
          chmod +x "$out"
          echo "intentional failure after output" >&2
          exit 3
          ;;
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

  def run(name : String, extra_env = {} of String => String?, timeout : String = "60")
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run(
      File.join(@root, "scripts/run_safe.sh"),
      ["/bin/bash", timeout, "512", "regression_tests/#{name}", "./compiler", "1"],
      chdir: @work, output: stdout, error: stderr,
      env: {"RUN_SAFE_PASSTHROUGH_STDIO" => nil, "RUN_SAFE_RESOURCE_FILE" => nil}.merge(extra_env)
    )
    {status.exit_code, "#{stdout}#{stderr}"}
  end

  def cleanup
    FileUtils.rm_rf(@work)
  end
end

describe "regression compilation supervision" do
  {"run_all.sh" => false, "run_combined.sh" => true}.each do |runner, combined|
    it "keeps stale files outside fresh compilation outputs in #{runner}" do
      fixture = RegressionRunnerFixture.new
      begin
        fixture.add("no_binary", combined)
        dir = File.join(fixture.work, combined ? "regression_tests/combined" : "regression_tests")
        FileUtils.mkdir_p(File.join(dir, "bin"))
        stale = [File.join(dir, "no_binary"), File.join(dir, "bin/no_binary")]
        stale.each do |path|
          File.write(path, "#!/bin/bash\ntouch stale_executed\nexit 0\n")
          File.chmod(path, 0o755)
        end
        rc, output = fixture.run(runner)
        rc.should eq(1), output
        output.should contain("FAIL (no binary): no_binary")
        File.exists?(File.join(fixture.work, "stale_executed")).should be_false
        stale.each { |path| File.exists?(path).should be_true }
      ensure
        fixture.cleanup
      end
    end

    it "rejects partial compilation output in #{runner}" do
      fixture = RegressionRunnerFixture.new
      begin
        fixture.add("partial_compile", combined)
        fixture.add("nonexec_compile", combined)
        rc, output = fixture.run(runner)
        rc.should eq(1), output
        output.should contain("FAIL (compile): partial_compile")
        output.should contain("FAIL (no binary): nonexec_compile")
        output.should contain("intentional failure after output")
        File.exists?(File.join(fixture.work, "partial_executed")).should be_false
      ensure
        fixture.cleanup
      end
    end

    it "cleans owned logs by default and can retain raw failure evidence in #{runner}" do
      fixture = RegressionRunnerFixture.new
      begin
        fixture.add("marker_exit7", combined)
        fixture.add("partial_compile", combined)
        logs_root = File.join(fixture.work, "logs")
        FileUtils.mkdir_p(logs_root)
        rc, output = fixture.run(runner, {"TMPDIR" => logs_root})
        rc.should eq(1), output
        Dir.children(logs_root).should be_empty

        rc, output = fixture.run(runner, {"TMPDIR" => logs_root, "REGRESSION_KEEP_LOGS" => "1"})
        rc.should eq(1), output
        dirs = Dir.children(logs_root)
        dirs.size.should eq(1)
        logs = File.join(logs_root, dirs.first)
        output.should contain("Logs: #{logs}")
        File.read(File.join(logs, "marker_exit7.compile.exit")).strip.should eq("0")
        File.read(File.join(logs, "marker_exit7.runtime.exit")).strip.should eq("7")
        File.read(File.join(logs, "marker_exit7.runtime.log")).should contain("MARKER")
        File.read(File.join(logs, "marker_exit7.result")).should start_with("CRASH\n")
        File.read(File.join(logs, "partial_compile.compile.exit")).strip.should eq("3")
        File.read(File.join(logs, "partial_compile.compile.log")).should contain("intentional failure after output")
        File.exists?(File.join(logs, "marker_exit7")).should be_false
        File.exists?(File.join(logs, "partial_compile")).should be_false
        File.exists?(File.join(logs, "marker_exit7.ll")).should be_false
        File.exists?(File.join(logs, "partial_compile.ll")).should be_false
        Dir.children(logs).all? { |entry| entry.ends_with?(".log") || entry.ends_with?(".exit") || entry.ends_with?(".result") }.should be_true
      ensure
        fixture.cleanup
      end
    end

    it "stops hung compilation and its child in #{runner}" do
      fixture = RegressionRunnerFixture.new
      begin
        fixture.add("compile_timeout", combined)
        rc, output = fixture.run(runner, {"REGRESSION_COMPILE_TIMEOUT" => "1"}, "10")
        rc.should eq(1), output
        output.should contain("FAIL (compile): compile_timeout")
        %w[compiler.pid compiler_child.pid].each do |name|
          pid = File.read(File.join(fixture.work, name)).strip.to_i
          deadline = Time.instant + 2.seconds
          while Process.exists?(pid) && Time.instant < deadline
            sleep 20.milliseconds
          end
          Process.exists?(pid).should be_false
        end
      ensure
        fixture.cleanup
      end
    end
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
