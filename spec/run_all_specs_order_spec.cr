require "spec"
require "file_utils"

describe "scripts/run_all_specs.sh manifest ordering" do
  it "defers only the two expensive specs after sorted ordinary specs" do
    root = File.expand_path("..", __DIR__)
    runner = File.join(root, "scripts", "run_all_specs.sh")
    temp_root = File.join(Dir.tempdir, "adamas_spec_order_#{Process.pid}_#{Random.rand(1_000_000)}")
    spec_dir = File.join(temp_root, "specs")
    lock_dir = File.join(temp_root, "lock")
    fake_crystal = File.join(temp_root, "crystal")
    fake_compiler = File.join(temp_root, "adamas-spec-compiler")
    order_file = File.join(temp_root, "order.log")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    FileUtils.mkdir_p(spec_dir)
    [
      "z_ordinary_spec.cr",
      "a_ordinary_spec.cr",
      "ordinary spaced_spec.cr",
      "other_integration_spec.cr",
      "generated_runtime_integration_spec.cr",
      "produced_stage_bootstrap_spec.cr",
    ].each do |name|
      File.write(File.join(spec_dir, name), "")
    end

    File.write(fake_compiler, "#!/usr/bin/env bash\nexit 0\n")
    File.chmod(fake_compiler, 0o755)
    File.write(fake_crystal, <<-'SH')
      #!/usr/bin/env bash
      set -euo pipefail

      case "${1:-}" in
        spec)
          printf '%s\n' "$(basename "${2:?}")" >>"${FAKE_ORDER:?}"
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
        ["1", "10", "256", spec_dir],
        env: {
          "ADAMAS_SPEC_RUN_LOCK_DIR" => lock_dir,
          "ADAMAS_SPEC_COMPILER"      => fake_compiler,
          "CRYSTAL_BIN"               => fake_crystal,
          "FAKE_ORDER"                => order_file,
        },
        output: stdout,
        error: stderr
      )
      output = "#{stdout}#{stderr}"

      status.success?.should be_true
      output.should contain("PASS=6")
      File.read(order_file).lines.map(&.chomp).should eq([
        "a_ordinary_spec.cr",
        "ordinary spaced_spec.cr",
        "other_integration_spec.cr",
        "z_ordinary_spec.cr",
        "generated_runtime_integration_spec.cr",
        "produced_stage_bootstrap_spec.cr",
      ])
    ensure
      if match = "#{stdout}#{stderr}".match(/Spec logs: (.+)/)
        FileUtils.rm_rf(match[1].strip)
      end
      FileUtils.rm_rf(temp_root)
    end
  end
end
