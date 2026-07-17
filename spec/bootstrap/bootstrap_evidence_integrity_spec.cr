require "spec"
require "file_utils"

module BootstrapEvidenceIntegritySpec
  def self.write_fake_compiler(path : String) : Nil
    File.write(path, <<-SH)
      #!/bin/sh
      set -eu
      out=""
      source=""
      need_out=0
      for arg in "$@"; do
        if [ "$need_out" = "1" ]; then
          out="$arg"
          need_out=0
          continue
        fi
        if [ "$arg" = "-o" ]; then
          need_out=1
          continue
        fi
        case "$arg" in
          *.cr) source="$arg" ;;
        esac
      done

      [ -n "$out" ] || exit 2
      mode="${FAKE_BOOTSTRAP_MODE:-good}"
      state="${FAKE_BOOTSTRAP_STATE:?}"
      plain_marker="${FAKE_BOOTSTRAP_PLAIN_MARKER:?}"
      no_prelude_marker="${FAKE_BOOTSTRAP_NOPRELUDE_MARKER:?}"

      case "$source" in
        */src/adamas.cr|src/adamas.cr)
          count="$(cat "$state" 2>/dev/null || printf '0')"
          count=$((count + 1))
          printf '%s\n' "$count" > "$state"
          if [ "$mode" = "no-output" ]; then
            exit 0
          fi
          if [ "$mode" = "stale" ] && [ "$count" -ge 2 ]; then
            exit 0
          fi
          cp "$0" "$out"
          chmod +x "$out"
          if [ "$mode" = "stale" ] && [ "$count" -eq 1 ]; then
            stale="$(dirname "$out")/cv2_s2"
            printf '#!/bin/sh\nexit 0\n' > "$stale"
            chmod +x "$stale"
          fi
          ;;
        */_smoke_puts42.cr)
          if [ "$mode" = "no-output" ] || { [ "$mode" = "stale" ] && [ "$(cat "$state")" -ge 2 ]; }; then
            exit 0
          fi
          printf '#!/bin/sh\nprintf "plain-ran\\n" >> "$FAKE_BOOTSTRAP_PLAIN_MARKER"\nprintf "42\\n"\n' > "$out"
          chmod +x "$out"
          ;;
        */test_no_prelude_interpolation.cr)
          if [ "$mode" = "no-output" ] || { [ "$mode" = "stale" ] && [ "$(cat "$state")" -ge 2 ]; }; then
            exit 0
          fi
          printf '#!/bin/sh\nprintf "no-prelude-ran\\n" >> "$FAKE_BOOTSTRAP_NOPRELUDE_MARKER"\nprintf "noprelude_interp_ok\\n"\n' > "$out"
          chmod +x "$out"
          ;;
        *)
          exit 3
          ;;
      esac
    SH
    File.chmod(path, 0o755)
  end

  def self.run_script(
    script : String,
    args : Array(String),
    env : Hash(String, String),
  ) : NamedTuple(status: Process::Status, stdout: String, stderr: String)
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run(script, args, env: env, output: stdout, error: stderr)
    {status: status, stdout: stdout.to_s, stderr: stderr.to_s}
  end

  def self.test_env(workdir : String, mode : String, plain_marker : String, no_prelude_marker : String) : Hash(String, String)
    {
      "FAKE_BOOTSTRAP_MODE" => mode,
      "FAKE_BOOTSTRAP_STATE" => File.join(workdir, "state"),
      "FAKE_BOOTSTRAP_PLAIN_MARKER" => plain_marker,
      "FAKE_BOOTSTRAP_NOPRELUDE_MARKER" => no_prelude_marker,
    }
  end
end

describe "bootstrap evidence integrity" do
  root = File.expand_path("../..", __DIR__)
  chain_script = File.join(root, "scripts", "bootstrap_chain.sh")
  stages_script = File.join(root, "scripts", "build_bootstrap_stages.sh")

  it "rejects an exit-zero compiler that leaves stale stage and smoke outputs" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_stale_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(workdir, "out")
    fake = File.join(workdir, "fake-compiler")
    plain_marker = File.join(workdir, "plain-ran")
    no_prelude_marker = File.join(workdir, "no-prelude-ran")
    FileUtils.mkdir_p(workdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      result = BootstrapEvidenceIntegritySpec.run_script(
        chain_script,
        ["--stages", "2", "--host", fake, "--out", outdir, "--timeout", "10", "--mem", "256"],
        BootstrapEvidenceIntegritySpec.test_env(workdir, "stale", plain_marker, no_prelude_marker)
      )

      result[:status].success?.should be_false
      (result[:stdout] + result[:stderr]).should contain("fresh stage artifact missing")
    ensure
      FileUtils.rm_rf(workdir)
    end
  end

  it "fails closed when an explicit output directory is reused" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_reuse_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(workdir, "out")
    fake = File.join(workdir, "fake-compiler")
    plain_marker = File.join(workdir, "plain-ran")
    no_prelude_marker = File.join(workdir, "no-prelude-ran")
    FileUtils.mkdir_p(workdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      first = BootstrapEvidenceIntegritySpec.run_script(
        chain_script,
        ["--stages", "1", "--host", fake, "--out", outdir, "--timeout", "10", "--mem", "256"],
        BootstrapEvidenceIntegritySpec.test_env(workdir, "good", plain_marker, no_prelude_marker)
      )
      first[:status].success?.should be_true, "#{first[:stdout]}\n#{first[:stderr]}"

      second = BootstrapEvidenceIntegritySpec.run_script(
        chain_script,
        ["--stages", "1", "--host", fake, "--out", outdir, "--timeout", "10", "--mem", "256"],
        BootstrapEvidenceIntegritySpec.test_env(workdir, "no-output", plain_marker, no_prelude_marker)
      )
      second[:status].success?.should be_false
      (second[:stdout] + second[:stderr]).should contain("output directory must be empty")
    ensure
      FileUtils.rm_rf(workdir)
    end
  end

  it "writes source, producer, output, flags, host, time, run, and cache evidence" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_manifest_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(workdir, "out")
    fake = File.join(workdir, "fake-compiler")
    plain_marker = File.join(workdir, "plain-ran")
    no_prelude_marker = File.join(workdir, "no-prelude-ran")
    FileUtils.mkdir_p(workdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      result = BootstrapEvidenceIntegritySpec.run_script(
        stages_script,
        ["--stages", "2", "--host", fake, "--out", outdir, "--timeout", "10", "--mem", "256"],
        BootstrapEvidenceIntegritySpec.test_env(workdir, "good", plain_marker, no_prelude_marker)
      )
      result[:status].success?.should be_true, "#{result[:stdout]}\n#{result[:stderr]}"

      manifest = File.read(File.join(outdir, "bootstrap_stages.manifest"))
      manifest.should contain("format_version=2")
      manifest.should contain("s1_bootstrap=cv2_s1")
      manifest.should contain("s2b=cv2_s2")
      manifest.should match(/run_id=[A-Za-z0-9._-]+/)
      manifest.should match(/source_tree_sha256=[0-9a-f]{64}/)
      manifest.should match(/source_content_sha256=[0-9a-f]{64}/)
      manifest.should contain("source_git_state=clean")
      manifest.should match(/source_git_status_sha256=[0-9a-f]{64}/)
      manifest.should match(/source_git_diff_sha256=[0-9a-f]{64}/)
      manifest.should contain("host_toolchain_identity=")
      manifest.should match(/harness_bootstrap_chain_sha256=[0-9a-f]{64}/)
      manifest.should match(/harness_run_safe_sha256=[0-9a-f]{64}/)
      manifest.should match(/stable_wrapper_sha256=[0-9a-f]{64}/)
      manifest.should match(/path_sha256=[0-9a-f]{64}/)
      manifest.should contain("cache_mode=")
      manifest.should match(/bootstrap_env_sha256=[0-9a-f]{64}/)
      manifest.should match(/stage1_flags_b64=[A-Za-z0-9+\/=]+/)
      manifest.should contain("stage1_flags_text=")
      manifest.should contain("--error-trace")
      manifest.should match(/stage1_producer_sha256=[0-9a-f]{64}/)
      manifest.should match(/stage2_producer_sha256=[0-9a-f]{64}/)
      manifest.should match(/stage1_output_sha256=[0-9a-f]{64}/)
      manifest.should match(/stage2_output_sha256=[0-9a-f]{64}/)
      manifest.should match(/stage1_build_started_at=/)
      manifest.should match(/stage1_build_finished_at=/)
      manifest.should match(/stage1_run_id=[A-Za-z0-9._-]+/)
      manifest.should match(/stage2_run_id=[A-Za-z0-9._-]+/)
    ensure
      FileUtils.rm_rf(workdir)
    end
  end
end
