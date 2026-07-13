require "spec"
require "file_utils"

describe "scripts/run_all_specs.sh invocation lock" do
  it "fails fast when the overridden lock belongs to a live process" do
    root = File.expand_path("..", __DIR__)
    runner = File.join(root, "scripts", "run_all_specs.sh")
    lock_dir = File.join(Dir.tempdir, "adamas_spec_lock_#{Process.pid}_#{Random.rand(1_000_000)}")
    missing_path = File.join(Dir.tempdir, "adamas_missing_specs_#{Process.pid}_#{Random.rand(1_000_000)}")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    Dir.mkdir(lock_dir)
    File.write(File.join(lock_dir, "pid"), "#{Process.pid}\n")

    begin
      status = Process.run(
        runner,
        ["1", "1", "128", missing_path],
        env: {"ADAMAS_SPEC_RUN_LOCK_DIR" => lock_dir},
        output: stdout,
        error: stderr
      )
      output = "#{stdout}#{stderr}"

      status.exit_code.should eq(3)
      output.should contain("run_all_specs.sh is already running for this repository")
      output.should contain("pid=#{Process.pid}")
      output.should contain(lock_dir)
      File.read(File.join(lock_dir, "pid")).strip.should eq(Process.pid.to_s)
    ensure
      if match = "#{stdout}#{stderr}".match(/Spec logs: (.+)/)
        FileUtils.rm_rf(match[1].strip)
      end
      FileUtils.rm_rf(lock_dir)
    end
  end

  it "reclaims a stale owner and releases the replacement lock on exit" do
    root = File.expand_path("..", __DIR__)
    runner = File.join(root, "scripts", "run_all_specs.sh")
    lock_dir = File.join(Dir.tempdir, "adamas_stale_spec_lock_#{Process.pid}_#{Random.rand(1_000_000)}")
    missing_path = File.join(Dir.tempdir, "adamas_missing_specs_#{Process.pid}_#{Random.rand(1_000_000)}")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    Dir.mkdir(lock_dir)
    File.write(File.join(lock_dir, "pid"), "2147483647\n")

    begin
      status = Process.run(
        runner,
        ["1", "1", "128", missing_path],
        env: {"ADAMAS_SPEC_RUN_LOCK_DIR" => lock_dir},
        output: stdout,
        error: stderr
      )
      output = "#{stdout}#{stderr}"

      status.exit_code.should eq(2)
      output.should contain("Reclaiming stale run_all_specs.sh lock")
      output.should contain("Spec path does not exist")
      Dir.exists?(lock_dir).should be_false
    ensure
      if match = "#{stdout}#{stderr}".match(/Spec logs: (.+)/)
        FileUtils.rm_rf(match[1].strip)
      end
      FileUtils.rm_rf(lock_dir)
    end
  end

  it "fails closed when an external cleanup removes its output directory" do
    root = File.expand_path("..", __DIR__)
    runner = File.join(root, "scripts", "run_all_specs.sh")
    lock_dir = File.join(Dir.tempdir, "adamas_removed_outdir_lock_#{Process.pid}_#{Random.rand(1_000_000)}")
    fake_dir = File.join(Dir.tempdir, "adamas_removed_outdir_fake_#{Process.pid}_#{Random.rand(1_000_000)}")
    fake_crystal = File.join(fake_dir, "crystal")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    Dir.mkdir(fake_dir)
    File.write(fake_crystal, <<-'SH')
      #!/usr/bin/env bash
      outdir="$(dirname "${CRYSTAL_CACHE_DIR:?}")"
      rm -rf "$outdir"
      echo "1 examples, 0 failures, 0 errors, 0 pending"
    SH
    File.chmod(fake_crystal, 0o755)

    begin
      status = Process.run(
        runner,
        ["1", "5", "128", "spec/run_all_specs_defaults_spec.cr"],
        env: {
          "ADAMAS_SPEC_RUN_LOCK_DIR" => lock_dir,
          "CRYSTAL_BIN"              => fake_crystal,
        },
        output: stdout,
        error: stderr
      )
      output = "#{stdout}#{stderr}"

      status.exit_code.should eq(1)
      output.should contain("Spec output directory disappeared during the run")
      Dir.exists?(lock_dir).should be_false
    ensure
      FileUtils.rm_rf(lock_dir)
      FileUtils.rm_rf(fake_dir)
    end
  end

  it "provisions ADAMAS_SPEC_COMPILER for the produced-stage bootstrap spec" do
    root = File.expand_path("..", __DIR__)
    runner = File.join(root, "scripts", "run_all_specs.sh")
    bootstrap_spec = File.join(root, "spec", "bootstrap", "produced_stage_bootstrap_spec.cr")
    lock_dir = File.join(Dir.tempdir, "adamas_generated_consumer_lock_#{Process.pid}_#{Random.rand(1_000_000)}")
    fake_dir = File.join(Dir.tempdir, "adamas_generated_consumer_fake_#{Process.pid}_#{Random.rand(1_000_000)}")
    fake_crystal = File.join(fake_dir, "crystal")
    observed_compiler = File.join(fake_dir, "observed-compiler.txt")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    Dir.mkdir(fake_dir)
    File.write(fake_crystal, <<-'SH')
      #!/usr/bin/env bash
      set -euo pipefail

      case "${1:-}" in
        build)
          shift
          output=""
          while [ "$#" -gt 0 ]; do
            if [ "$1" = "-o" ]; then
              output="$2"
              break
            fi
            shift
          done
          test -n "$output"
          printf '#!/usr/bin/env bash\nexit 0\n' >"$output"
          chmod +x "$output"
          ;;
        spec)
          test -n "${ADAMAS_SPEC_COMPILER:-}"
          test -x "$ADAMAS_SPEC_COMPILER"
          printf '%s\n' "$ADAMAS_SPEC_COMPILER" >"${FAKE_STATE:?}"
          echo "1 examples, 0 failures, 0 errors, 0 pending"
          ;;
        *)
          echo "unexpected fake crystal command: ${1:-<missing>}" >&2
          exit 22
          ;;
      esac
    SH
    File.chmod(fake_crystal, 0o755)

    begin
      status = Process.run(
        runner,
        ["1", "10", "256", bootstrap_spec],
        env: {
          "ADAMAS_SPEC_RUN_LOCK_DIR" => lock_dir,
          "ADAMAS_SPEC_COMPILER"      => "",
          "CRYSTAL_BIN"               => fake_crystal,
          "FAKE_STATE"                => observed_compiler,
        },
        output: stdout,
        error: stderr
      )
      output = "#{stdout}#{stderr}"

      status.success?.should be_true
      output.should contain("Building fresh generated-spec compiler")
      output.should contain("PASS=")
      File.exists?(observed_compiler).should be_true
      generated_compiler = File.read(observed_compiler).strip
      File.basename(generated_compiler).should eq("adamas-spec-compiler")
      File.exists?(generated_compiler).should be_false
      Dir.exists?(lock_dir).should be_false
    ensure
      if match = "#{stdout}#{stderr}".match(/Spec logs: (.+)/)
        FileUtils.rm_rf(match[1].strip)
      end
      FileUtils.rm_rf(lock_dir)
      FileUtils.rm_rf(fake_dir)
    end
  end
end
