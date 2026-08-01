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
      if [ "$mode" = "require-sanitized-env" ] && [ "${CC+x}" = "x" ]; then
        exit 9
      fi

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
          case "$mode" in
            symlink-output) ln -s "$0" "$out" ;;
            hardlink-output) ln "$0" "$out" ;;
            *) cp "$0" "$out" ;;
          esac
          chmod +x "$out"
          if [ "$mode" = "manifest-collision" ]; then
            printf 'target-owned\n' > "$(dirname "$out")/bootstrap_chain.manifest"
          fi
          if [ "$mode" = "build-log-symlink" ]; then
            stage="$(basename "$out" | sed 's/^cv2_s//')"
            rm -f "$(dirname "$out")/stage${stage}_build.log"
            ln -s "$out" "$(dirname "$out")/stage${stage}_build.log"
          fi
          if [ "$mode" = "stale" ] && [ "$count" -eq 1 ]; then
            stale="$(dirname "$out")/cv2_s2"
            printf '#!/bin/sh\nexit 0\n' > "$stale"
            chmod +x "$stale"
          fi
          ;;
        */_smoke_puts42.cr)
          if [ "$mode" = "smoke-extra" ]; then
            printf '#!/bin/sh\nprintf "42\\nextra\\n"\n' > "$out"
          elif [ "$mode" = "smoke-blank" ]; then
            printf '#!/bin/sh\nprintf "42\\n\\n"\n' > "$out"
          elif [ "$mode" = "smoke-stderr" ]; then
            printf '#!/bin/sh\nprintf "42\\n"\nprintf "contamination\\n" >&2\n' > "$out"
          elif [ "$mode" = "smoke-header-spoof" ]; then
            printf '#!/bin/sh\nprintf "=== STDOUT ===\\n42\\n"\n' > "$out"
          else
            printf '#!/bin/sh\nprintf "42\\n"\n' > "$out"
          fi
          chmod +x "$out"
          if [ "$mode" = "mutate-producer" ]; then printf '# mutation\n' >> "$0"; fi
          if [ "$mode" = "mutate-build-log-after-read" ]; then
            stage="$(basename "$0" | sed 's/^cv2_s//')"
            printf 'late mutation\n' >> "$(dirname "$0")/stage${stage}_build.log"
          fi
          ;;
        */test_no_prelude_interpolation.cr)
          printf '#!/bin/sh\nprintf "noprelude_interp_ok\\n"\n' > "$out"
          chmod +x "$out"
          if [ "$mode" = "mutate-producer" ]; then printf '# mutation\n' >> "$0"; fi
          ;;
        *)
          exit 3
          ;;
      esac
    SH
    File.chmod(path, 0o755)
  end

  def self.run_chain(
    chain_script : String,
    workdir : String,
    outdir : String,
    fake : String,
    mode : String,
    stages = 2,
    extra_env = Hash(String, String).new,
  ) : NamedTuple(status: Process::Status, output: String)
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    env = {
      "FAKE_BOOTSTRAP_MODE"  => mode,
      "FAKE_BOOTSTRAP_STATE" => File.join(workdir, "state"),
    }
    extra_env.each { |key, value| env[key] = value }
    status = Process.run(
      chain_script,
      ["--stages", stages.to_s, "--host", fake, "--out", outdir, "--timeout", "10", "--mem", "256"],
      env: env,
      output: stdout,
      error: stderr
    )
    {status: status, output: "#{stdout}#{stderr}"}
  end

  def self.manifest_fields(path : String) : Hash(String, String)
    fields = Hash(String, String).new
    File.each_line(path) do |line|
      key, value = line.chomp.split("=", 2)
      raise "duplicate manifest field: #{key}" if fields.has_key?(key)
      fields[key] = value
    end
    fields
  end
end

describe "bootstrap evidence integrity" do
  root = File.expand_path("../..", __DIR__)
  chain_script = File.join(root, "scripts", "bootstrap_chain.sh")

  it "rejects an exit-zero compiler that leaves a stale stage output" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_stale_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(workdir, "out")
    fake = File.join(workdir, "fake-compiler")
    FileUtils.mkdir_p(workdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      result = BootstrapEvidenceIntegritySpec.run_chain(chain_script, workdir, outdir, fake, "stale")

      result[:status].success?.should be_false
      result[:output].should contain("stage output path already exists")
      BootstrapEvidenceIntegritySpec.manifest_fields(File.join(outdir, "bootstrap_chain.manifest"))["status"].should eq("failed")
    ensure
      FileUtils.rm_rf(workdir)
    end
  end

  it "rejects contaminating compiler-control environment before target launch" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_env_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(workdir, "out")
    fake = File.join(workdir, "fake-compiler")
    FileUtils.mkdir_p(workdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      [{"ADAMAS_LLVM_WORKERS" => "1"}, {"CRYSTAL_WORKERS" => "1"}].each_with_index do |extra_env, index|
        result = BootstrapEvidenceIntegritySpec.run_chain(
          chain_script,
          workdir,
          "#{outdir}_#{index}",
          fake,
          "good",
          stages: 1,
          extra_env: extra_env
        )

        result[:status].success?.should be_false
        result[:output].should contain("bootstrap control environment must be unset")
      end
      File.exists?(File.join(workdir, "state")).should be_false
    ensure
      FileUtils.rm_rf(workdir)
    end
  end

  it "sanitizes generic compiler environment before target launch" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_sanitized_env_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(workdir, "out")
    fake = File.join(workdir, "fake-compiler")
    FileUtils.mkdir_p(workdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      result = BootstrapEvidenceIntegritySpec.run_chain(
        chain_script,
        workdir,
        outdir,
        fake,
        "require-sanitized-env",
        stages: 1,
        extra_env: {"CC" => "/tmp/not-the-compiler"}
      )

      result[:status].success?.should be_true, result[:output]
      fields = BootstrapEvidenceIntegritySpec.manifest_fields(File.join(outdir, "bootstrap_chain.manifest"))
      fields["compiler_environment_policy"].should eq("known_controls_unset")
    ensure
      FileUtils.rm_rf(workdir)
    end
  end

  it "fails closed when an explicit output directory is reused" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_reuse_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(workdir, "out")
    fake = File.join(workdir, "fake-compiler")
    FileUtils.mkdir_p(workdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      first = BootstrapEvidenceIntegritySpec.run_chain(chain_script, workdir, outdir, fake, "good", stages: 1)
      first[:status].success?.should be_true, first[:output]

      second = BootstrapEvidenceIntegritySpec.run_chain(chain_script, workdir, outdir, fake, "no-output", stages: 1)
      second[:status].success?.should be_false
      second[:output].should contain("output directory must not already exist")
    ensure
      FileUtils.rm_rf(workdir)
    end
  end

  it "rejects an explicitly supplied output directory even when it is empty" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_empty_out_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(workdir, "out")
    fake = File.join(workdir, "fake-compiler")
    FileUtils.mkdir_p(outdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      result = BootstrapEvidenceIntegritySpec.run_chain(chain_script, workdir, outdir, fake, "good", stages: 1)

      result[:status].success?.should be_false
      result[:output].should contain("output directory must not already exist")
      File.exists?(File.join(workdir, "state")).should be_false
    ensure
      FileUtils.rm_rf(workdir)
    end
  end

  it "rejects an output path inside source scope before creating it" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_source_out_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(root, "src", ".bootstrap-rejected-#{Process.pid}-#{Random.rand(1_000_000)}")
    fake = File.join(workdir, "fake-compiler")
    FileUtils.mkdir_p(workdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      result = BootstrapEvidenceIntegritySpec.run_chain(chain_script, workdir, outdir, fake, "good", stages: 1)

      result[:status].success?.should be_false
      result[:output].should contain("output directory must be outside source evidence scope")
      File.exists?(outdir).should be_false
      File.exists?(File.join(workdir, "state")).should be_false
    ensure
      FileUtils.rm_rf(outdir)
      FileUtils.rm_rf(workdir)
    end
  end

  it "canonicalizes a relative output parent before source-scope admission" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_relative_out_#{Process.pid}_#{Random.rand(1_000_000)}")
    relative_out = File.join("src", ".bootstrap-relative-rejected-#{Process.pid}-#{Random.rand(1_000_000)}")
    absolute_out = File.join(root, relative_out)
    fake = File.join(workdir, "fake-compiler")
    FileUtils.mkdir_p(workdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      result = BootstrapEvidenceIntegritySpec.run_chain(chain_script, workdir, relative_out, fake, "good", stages: 1)

      result[:status].success?.should be_false
      result[:output].should contain("output directory must be outside source evidence scope")
      File.exists?(absolute_out).should be_false
      File.exists?(File.join(workdir, "state")).should be_false
    ensure
      FileUtils.rm_rf(absolute_out)
      FileUtils.rm_rf(workdir)
    end
  end

  it "canonicalizes a symlinked output parent before source-scope admission" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_symlink_parent_#{Process.pid}_#{Random.rand(1_000_000)}")
    linked_parent = File.join(workdir, "source-link")
    outdir = File.join(linked_parent, ".bootstrap-symlink-rejected-#{Process.pid}-#{Random.rand(1_000_000)}")
    resolved_out = File.join(root, "src", File.basename(outdir))
    fake = File.join(workdir, "fake-compiler")
    FileUtils.mkdir_p(workdir)
    File.symlink(File.join(root, "src"), linked_parent)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      result = BootstrapEvidenceIntegritySpec.run_chain(chain_script, workdir, outdir, fake, "good", stages: 1)

      result[:status].success?.should be_false
      result[:output].should contain("output directory must be outside source evidence scope")
      File.exists?(resolved_out).should be_false
      File.exists?(File.join(workdir, "state")).should be_false
    ensure
      FileUtils.rm_rf(resolved_out)
      FileUtils.rm_rf(workdir)
    end
  end

  it "rejects symlinked and hardlinked stage artifacts" do
    {"symlink-output", "hardlink-output"}.each do |mode|
      workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_#{mode}_#{Process.pid}_#{Random.rand(1_000_000)}")
      outdir = File.join(workdir, "out")
      fake = File.join(workdir, "fake-compiler")
      FileUtils.mkdir_p(workdir)
      begin
        BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
        result = BootstrapEvidenceIntegritySpec.run_chain(chain_script, workdir, outdir, fake, mode, stages: 1)

        result[:status].success?.should be_false, mode
        result[:output].should contain("fresh stage executable contract failed"), mode
      ensure
        FileUtils.rm_rf(workdir)
      end
    end
  end

  it "rejects extra or blank stdout, target stderr, and control-header spoofing" do
    {"smoke-extra", "smoke-blank", "smoke-stderr", "smoke-header-spoof"}.each do |mode|
      workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_#{mode}_#{Process.pid}_#{Random.rand(1_000_000)}")
      outdir = File.join(workdir, "out")
      fake = File.join(workdir, "fake-compiler")
      FileUtils.mkdir_p(workdir)
      begin
        BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
        result = BootstrapEvidenceIntegritySpec.run_chain(chain_script, workdir, outdir, fake, mode, stages: 1)

        result[:status].success?.should be_false, mode
        result[:output].should contain("smoke runtime transcript mismatch"), mode
      ensure
        FileUtils.rm_rf(workdir)
      end
    end
  end

  it "rejects evidence changed after its first validation" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_late_mutation_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(workdir, "out")
    fake = File.join(workdir, "fake-compiler")
    FileUtils.mkdir_p(workdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      result = BootstrapEvidenceIntegritySpec.run_chain(
        chain_script,
        workdir,
        outdir,
        fake,
        "mutate-build-log-after-read",
        stages: 1
      )

      result[:status].success?.should be_false
      result[:output].should contain("evidence changed before manifest publication")
    ensure
      FileUtils.rm_rf(workdir)
    end
  end

  it "rejects producer mutation and symlinked build logs" do
    {"mutate-producer", "build-log-symlink"}.each do |mode|
      workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_#{mode}_#{Process.pid}_#{Random.rand(1_000_000)}")
      outdir = File.join(workdir, "out")
      fake = File.join(workdir, "fake-compiler")
      FileUtils.mkdir_p(workdir)
      begin
        BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
        result = BootstrapEvidenceIntegritySpec.run_chain(chain_script, workdir, outdir, fake, mode, stages: 1)

        result[:status].success?.should be_false, mode
      ensure
        FileUtils.rm_rf(workdir)
      end
    end
  end

  it "fails if the manifest destination appears before atomic publication" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_manifest_collision_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(workdir, "out")
    fake = File.join(workdir, "fake-compiler")
    FileUtils.mkdir_p(workdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      result = BootstrapEvidenceIntegritySpec.run_chain(chain_script, workdir, outdir, fake, "manifest-collision", stages: 1)

      result[:status].success?.should be_false
      result[:output].should contain("bootstrap provenance manifest was not published")
      File.read(File.join(outdir, "bootstrap_chain.manifest")).should eq("target-owned\n")
    ensure
      FileUtils.rm_rf(workdir)
    end
  end

  it "writes a producer-owned manifest with source, lineage, resource, smoke, cache, and harness evidence" do
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_evidence_manifest_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(workdir, "out")
    fake = File.join(workdir, "fake-compiler")
    FileUtils.mkdir_p(workdir)
    begin
      BootstrapEvidenceIntegritySpec.write_fake_compiler(fake)
      result = BootstrapEvidenceIntegritySpec.run_chain(chain_script, workdir, outdir, fake, "good")
      result[:status].success?.should be_true, result[:output]

      manifest_path = File.join(outdir, "bootstrap_chain.manifest")
      fields = BootstrapEvidenceIntegritySpec.manifest_fields(manifest_path)
      fields["manifest_schema"].should eq("bootstrap_chain_v3")
      fields["status"].should eq("success")
      fields["source_hash_consistent"].should eq("1")
      fields["source_tree_sha256_start"].should match(/\A[0-9a-f]{64}\z/)
      fields["source_tree_sha256_end"].should eq(fields["source_tree_sha256_start"])
      fields["host_compiler_sha256"].should match(/\A[0-9a-f]{64}\z/)
      fields["harness_bootstrap_chain_sha256"].should match(/\A[0-9a-f]{64}\z/)
      fields["harness_run_safe_sha256"].should match(/\A[0-9a-f]{64}\z/)
      fields["harness_evidence_contract_sha256"].should match(/\A[0-9a-f]{64}\z/)
      fields["smoke_plain_source_sha256"].should match(/\A[0-9a-f]{64}\z/)
      fields["smoke_noprelude_oracle_sha256_start"].should match(/\A[0-9a-f]{64}\z/)
      fields["smoke_noprelude_oracle_sha256_end"].should eq(fields["smoke_noprelude_oracle_sha256_start"])
      fields["source_consistency_model"].should eq("endpoint_before_after")
      fields["run_directory_policy"].should eq("producer_created_absent_path")
      fields["run_directory_identity"].should match(/\A[0-9]+:[0-9]+\z/)
      fields["cache_policy"].should eq("producer_created_empty")
      fields["cache_directory_identity"].should match(/\A[0-9]+:[0-9]+\z/)
      fields["worker_policy"].should eq("crystal_workers_unset")
      fields["environment_path_sha256"].should match(/\A[0-9a-f]{64}\z/)
      fields["stage1_output_sha256"].should match(/\A[0-9a-f]{64}\z/)
      fields["stage2_producer_sha256"].should eq(fields["stage1_output_sha256"])
      fields["stage2_output_sha256"].should match(/\A[0-9a-f]{64}\z/)
      fields["stage2_build_mode"].should eq("normal_binary")
      fields["stage2_build_wall_sec"].should match(/\A[0-9]+(?:\.[0-9]+)?\z/)
      fields["stage2_resource_schema"].should eq("run_safe_resource_v1")
      fields["stage2_resource_sha256"].should match(/\A[0-9a-f]{64}\z/)
      fields["stage2_smoke_plain_status"].should eq("ok")
      fields["stage2_smoke_plain_expected"].should eq("42")
      fields["stage2_smoke_noprelude_status"].should eq("ok")
      fields["stage2_smoke_noprelude_expected"].should eq("noprelude_interp_ok")
    ensure
      FileUtils.rm_rf(workdir)
    end
  end
end
