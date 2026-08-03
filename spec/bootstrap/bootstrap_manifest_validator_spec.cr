require "spec"
require "base64"
require "digest/sha256"
require "file_utils"

module BootstrapManifestValidatorSpec
  alias Fixture = NamedTuple(workdir: String, run_dir: String, host: String, manifest: String)

  def self.sha256_file(path : String) : String
    Digest::SHA256.hexdigest(File.read(path))
  end

  def self.sha256_text(text : String) : String
    Digest::SHA256.hexdigest(text)
  end

  def self.capture(command : String, args : Array(String)) : String
    output = IO::Memory.new
    status = Process.run(command, args, output: output)
    raise "command failed: #{command} #{args.join(" ")}" unless status.success?
    output.to_s
  end

  def self.collect_regular_files(path : String, files : Array(String)) : Nil
    Dir.each_child(path) do |entry|
      child = File.join(path, entry)
      if File.directory?(child) && !File.symlink?(child)
        collect_regular_files(child, files)
      elsif File.file?(child) && !File.symlink?(child)
        files << child
      end
    end
  end

  def self.source_tree_sha256(root : String) : String
    files = [] of String
    collect_regular_files(File.join(root, "src"), files)
    lines = files.map do |path|
      relative = path.byte_slice(root.bytesize + 1)
      "#{sha256_file(path)}  #{relative}"
    end
    sha256_text("#{lines.sort.join("\n")}\n")
  end

  def self.stat_identity(path : String) : String
    if capture("uname", ["-s"]).strip == "Darwin"
      capture("stat", ["-f", "%d:%i", path]).strip
    else
      capture("stat", ["-c", "%d:%i", "--", path]).strip
    end
  end

  def self.resource_row(max_rss = "128", max_fd = "8") : String
    "[RUN_SAFE_RESOURCE] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=0 " +
      "max_rss_kb=#{max_rss} max_fd=#{max_fd} rss_samples=2 fd_samples=2 " +
      "rss_available=yes fd_available=yes process_tree_mode=ps_ancestry_snapshot " +
      "tree_coverage=all_scheduled_snapshots fd_tree_coverage=all_stable_pairs " +
      "tree_samples=2 fd_topology_stable_samples=2 fd_topology_unstable_samples=0 max_tree_pids=1\n"
  end

  def self.runtime_log(marker : String) : String
    "=== STDOUT ===\n#{marker}\n=== STDERR ===\n" +
      "[EXIT: 0] after ~1s\n#{resource_row}"
  end

  def self.build_log(wall_sec : String) : String
    "=== STDOUT ===\n=== STDERR ===\n[EXIT: 0] after ~1s\n" +
      resource_row + "real #{wall_sec}\nuser 0.00\nsys 0.00\n"
  end

  def self.write_executable(path : String, body = "#!/bin/sh\nexit 0\n") : Nil
    File.write(path, body)
    File.chmod(path, 0o755)
  end

  def self.write_manifest(path : String, fields : Hash(String, String)) : Nil
    File.write(path, fields.map { |key, value| "#{key}=#{value}\n" }.join)
  end

  def self.update_manifest(path : String, key : String, value : String) : Nil
    lines = File.read_lines(path)
    replaced = false
    lines.map! do |line|
      if line.starts_with?("#{key}=")
        replaced = true
        "#{key}=#{value}"
      else
        line
      end
    end
    raise "missing manifest key: #{key}" unless replaced
    File.write(path, "#{lines.join("\n")}\n")
  end

  def self.create_fixture(root : String) : Fixture
    workdir = File.join(Dir.tempdir, "adamas_manifest_validator_#{Process.pid}_#{Random.rand(1_000_000)}")
    run_dir = File.join(workdir, "run")
    cache_dir = File.join(run_dir, "cache")
    FileUtils.mkdir_p(cache_dir)
    File.chmod(run_dir, 0o700)
    File.chmod(cache_dir, 0o700)

    host_path = File.join(workdir, "trusted-crystal")
    write_executable(host_path)
    host = File.realpath(host_path)
    smoke_source = File.join(run_dir, "_smoke_puts42.cr")
    File.write(smoke_source, "puts 42\n")

    1.upto(2) do |stage|
      wall_sec = stage == 2 ? "300.00" : "10.0"
      write_executable(File.join(run_dir, "cv2_s#{stage}"), "#!/bin/sh\n# stage #{stage}\nexit 0\n")
      File.write(File.join(run_dir, "stage#{stage}_build.log"), build_log(wall_sec))
      File.write(File.join(run_dir, "stage#{stage}_build.resource"), resource_row)
      write_executable(File.join(run_dir, "stage#{stage}_smoke_plain.bin"))
      write_executable(File.join(run_dir, "stage#{stage}_smoke_noprelude.bin"))
      File.write(File.join(run_dir, "stage#{stage}_smoke_plain.log"), "plain compile stage #{stage}\n")
      File.write(File.join(run_dir, "stage#{stage}_smoke_noprelude.log"), "noprelude compile stage #{stage}\n")
      File.write(File.join(run_dir, "stage#{stage}_smoke_plain.runtime.log"), runtime_log("42"))
      File.write(
        File.join(run_dir, "stage#{stage}_smoke_noprelude.runtime.log"),
        runtime_log("hello world\nn=42\nnoprelude_interp_ok")
      )
    end

    source_status = capture("git", ["-C", root, "status", "--porcelain=v1", "--untracked-files=all", "--", "src"])
    source_diff = capture("git", ["-C", root, "diff", "--no-ext-diff", "--binary", "--", "src"])
    source_hash = sha256_file(File.join(root, "src", "adamas.cr"))
    source_tree_hash = source_tree_sha256(root)
    fields = {
      "manifest_schema"                             => "bootstrap_chain_v3",
      "run_id"                                      => "fixture-#{Process.pid}",
      "run_started_at"                              => "2026-07-31T00:00:00Z",
      "run_finished_at"                             => "2026-07-31T00:01:00Z",
      "status"                                      => "success",
      "requested_stages"                            => "2",
      "recorded_stages"                             => "2",
      "failed_stage"                                => "none",
      "failed_kind"                                 => "none",
      "source_rel_b64"                              => Base64.strict_encode("src/adamas.cr"),
      "source_scope_rel_b64"                        => Base64.strict_encode("src"),
      "source_content_sha256_start"                 => source_hash,
      "source_content_sha256_end"                   => source_hash,
      "source_tree_sha256_start"                    => source_tree_hash,
      "source_tree_sha256_end"                      => source_tree_hash,
      "source_hash_consistent"                      => "1",
      "source_git_head"                             => capture("git", ["-C", root, "rev-parse", "HEAD"]).strip,
      "source_git_status_sha256"                    => sha256_text(source_status),
      "source_git_diff_sha256"                      => sha256_text(source_diff),
      "source_consistency_model"                    => "endpoint_before_after",
      "host_compiler_b64"                           => Base64.strict_encode(host),
      "host_compiler_sha256"                        => sha256_file(host),
      "harness_bootstrap_chain_sha256"              => sha256_file(File.join(root, "scripts", "bootstrap_chain.sh")),
      "harness_run_safe_sha256"                     => sha256_file(File.join(root, "scripts", "run_safe.sh")),
      "harness_evidence_contract_sha256"            => sha256_file(File.join(root, "scripts", "lib", "bootstrap_evidence_contract.sh")),
      "smoke_plain_source_rel"                      => "_smoke_puts42.cr",
      "smoke_plain_source_sha256"                   => sha256_file(smoke_source),
      "smoke_noprelude_oracle_rel"                  => "regression_tests/combined/test_no_prelude_interpolation.cr",
      "smoke_noprelude_oracle_sha256_start"         => sha256_file(File.join(root, "regression_tests", "combined", "test_no_prelude_interpolation.cr")),
      "smoke_noprelude_oracle_sha256_end"           => sha256_file(File.join(root, "regression_tests", "combined", "test_no_prelude_interpolation.cr")),
      "environment_path_sha256"                     => "1" * 64,
      "environment_home_sha256"                     => "2" * 64,
      "environment_tmpdir_sha256"                   => "3" * 64,
      "compiler_environment_policy"                 => "known_controls_unset",
      "compiler_environment_sanitized_names_sha256" => "4" * 64,
      "run_directory_policy"                        => "producer_created_absent_path",
      "run_directory_identity"                      => stat_identity(run_dir),
      "cache_policy"                                => "producer_created_empty",
      "cache_dir_rel"                               => "cache",
      "cache_directory_identity"                    => stat_identity(cache_dir),
      "worker_policy"                               => "crystal_workers_unset",
    }

    1.upto(2) do |stage|
      output = File.join(run_dir, "cv2_s#{stage}")
      producer_hash = stage == 1 ? sha256_file(host) : sha256_file(File.join(run_dir, "cv2_s#{stage - 1}"))
      fields["stage#{stage}_status"] = "ok"
      fields["stage#{stage}_build_mode"] = "normal_binary"
      fields["stage#{stage}_build_started_at"] = "2026-07-31T00:00:00Z"
      fields["stage#{stage}_build_finished_at"] = "2026-07-31T00:00:30Z"
      fields["stage#{stage}_build_wall_sec"] = stage == 2 ? "300.00" : "10.0"
      flags = stage == 1 ? "build src/adamas.cr -o cv2_s1 --error-trace" : "src/adamas.cr -o cv2_s2"
      fields["stage#{stage}_flags_b64"] = Base64.strict_encode(flags)
      fields["stage#{stage}_producer_sha256"] = producer_hash
      fields["stage#{stage}_producer_sha256_end"] = producer_hash
      fields["stage#{stage}_producer_matches_previous_output"] = stage == 1 ? "not_applicable" : "yes"
      fields["stage#{stage}_output_rel"] = "cv2_s#{stage}"
      fields["stage#{stage}_output_sha256"] = sha256_file(output)
      fields["stage#{stage}_output_sha256_end"] = sha256_file(output)
      fields["stage#{stage}_build_log_rel"] = "stage#{stage}_build.log"
      fields["stage#{stage}_build_log_sha256"] = sha256_file(File.join(run_dir, "stage#{stage}_build.log"))
      fields["stage#{stage}_resource_rel"] = "stage#{stage}_build.resource"
      fields["stage#{stage}_resource_sha256"] = sha256_file(File.join(run_dir, "stage#{stage}_build.resource"))
      fields["stage#{stage}_resource_schema"] = "run_safe_resource_v1"
      {"plain" => "42", "noprelude" => "noprelude_interp_ok"}.each do |mode, expected|
        prefix = "stage#{stage}_smoke_#{mode}"
        fields["#{prefix}_status"] = "ok"
        fields["#{prefix}_expected"] = expected
        fields["#{prefix}_binary_rel"] = "#{prefix}.bin"
        fields["#{prefix}_compile_log_rel"] = "#{prefix}.log"
        fields["#{prefix}_runtime_log_rel"] = "#{prefix}.runtime.log"
        fields["#{prefix}_binary_sha256"] = sha256_file(File.join(run_dir, "#{prefix}.bin"))
        fields["#{prefix}_compile_log_sha256"] = sha256_file(File.join(run_dir, "#{prefix}.log"))
        fields["#{prefix}_log_sha256"] = sha256_file(File.join(run_dir, "#{prefix}.runtime.log"))
      end
    end

    manifest = File.join(run_dir, "bootstrap_chain.manifest")
    write_manifest(manifest, fields)
    {workdir: workdir, run_dir: run_dir, host: host, manifest: manifest}
  end

  def self.run_validator(validator : String, fixture : Fixture, max_wall = "300") : NamedTuple(status: Process::Status, output: String)
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run(
      validator,
      ["--run-dir", fixture[:run_dir], "--expected-host", fixture[:host], "--max-stage2-wall-sec", max_wall],
      output: stdout,
      error: stderr
    )
    {status: status, output: "#{stdout}#{stderr}"}
  end
end

describe "bootstrap manifest validator" do
  root = File.expand_path("../..", __DIR__)
  validator = File.join(root, "scripts", "validate_bootstrap_manifest.sh")

  it "accepts a complete fresh two-stage readiness vector" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_true, result[:output]
      result[:output].should contain("bootstrap_manifest_ready")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "accepts the exact 300-second stage2 boundary" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      build_log = File.join(fixture[:run_dir], "stage2_build.log")
      File.write(build_log, BootstrapManifestValidatorSpec.build_log("300.00"))
      BootstrapManifestValidatorSpec.update_manifest(fixture[:manifest], "stage2_build_wall_sec", "300.00")
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "stage2_build_log_sha256",
        BootstrapManifestValidatorSpec.sha256_file(build_log)
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture, "300.00")
      result[:status].success?.should be_true, result[:output]
      result[:output].should contain("bootstrap_manifest_ready")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects artifact tampering after manifest publication" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      File.open(File.join(fixture[:run_dir], "cv2_s2"), "a") { |file| file << "tampered\n" }
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("artifact_hash")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects semantic transcript tampering even when its manifest hash is updated" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      log = File.join(fixture[:run_dir], "stage2_smoke_plain.runtime.log")
      File.write(log, BootstrapManifestValidatorSpec.runtime_log("wrong"))
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "stage2_smoke_plain_log_sha256",
        BootstrapManifestValidatorSpec.sha256_file(log)
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("smoke_transcript")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects reordered no-prelude output even when its manifest hash is updated" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      log = File.join(fixture[:run_dir], "stage2_smoke_noprelude.runtime.log")
      File.write(log, BootstrapManifestValidatorSpec.runtime_log("n=42\nhello world\nnoprelude_interp_ok"))
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "stage2_smoke_noprelude_log_sha256",
        BootstrapManifestValidatorSpec.sha256_file(log)
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("smoke_transcript")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects trailing transcript bytes even when its manifest hash is updated" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      log = File.join(fixture[:run_dir], "stage2_smoke_plain.runtime.log")
      File.open(log, "a") { |file| file << "trailing\n" }
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "stage2_smoke_plain_log_sha256",
        BootstrapManifestValidatorSpec.sha256_file(log)
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("smoke_transcript")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects a forged smoke resource outcome even when its manifest hash is updated" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      log = File.join(fixture[:run_dir], "stage2_smoke_plain.runtime.log")
      forged = BootstrapManifestValidatorSpec.runtime_log("42").sub("exit_code=0", "exit_code=1")
      File.write(log, forged)
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "stage2_smoke_plain_log_sha256",
        BootstrapManifestValidatorSpec.sha256_file(log)
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("smoke_transcript")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects stage2 wall time above the policy boundary" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      build_log = File.join(fixture[:run_dir], "stage2_build.log")
      File.write(build_log, BootstrapManifestValidatorSpec.build_log("300.01"))
      BootstrapManifestValidatorSpec.update_manifest(fixture[:manifest], "stage2_build_wall_sec", "300.01")
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "stage2_build_log_sha256",
        BootstrapManifestValidatorSpec.sha256_file(build_log)
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("stage2_wall_budget")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects wall precision outside the producer time grammar" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      build_log = File.join(fixture[:run_dir], "stage2_build.log")
      wall = "180.000000000000001"
      File.write(build_log, BootstrapManifestValidatorSpec.build_log(wall))
      BootstrapManifestValidatorSpec.update_manifest(fixture[:manifest], "stage2_build_wall_sec", wall)
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "stage2_build_log_sha256",
        BootstrapManifestValidatorSpec.sha256_file(build_log)
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("build_policy")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "does not allow the caller to relax the fixed 300-second budget" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture, "300.01")
      result[:status].success?.should be_false
      result[:output].should contain("stage2_wall_policy")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "binds the manifest wall scalar to the hashed build log" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      BootstrapManifestValidatorSpec.update_manifest(fixture[:manifest], "stage2_build_wall_sec", "1")
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("stage_wall_evidence")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "binds the stage1 wall scalar to the hashed build log" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      BootstrapManifestValidatorSpec.update_manifest(fixture[:manifest], "stage1_build_wall_sec", "1")
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("stage_wall_evidence")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects multiple build resource rows instead of selecting the last wall" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      build_log = File.join(fixture[:run_dir], "stage2_build.log")
      ambiguous = BootstrapManifestValidatorSpec.build_log("1") +
                  BootstrapManifestValidatorSpec.resource_row +
                  "real 180\nuser 0.00\nsys 0.00\n"
      File.write(build_log, ambiguous)
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "stage2_build_log_sha256",
        BootstrapManifestValidatorSpec.sha256_file(build_log)
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("stage_wall_evidence")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "joins the build-log resource row to the producer-owned receipt" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      build_log = File.join(fixture[:run_dir], "stage2_build.log")
      valid_row = BootstrapManifestValidatorSpec.resource_row
      forged_row = valid_row.sub("exit_code=0", "exit_code=1")
      File.write(build_log, BootstrapManifestValidatorSpec.build_log("300.00").sub(valid_row, forged_row))
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "stage2_build_log_sha256",
        BootstrapManifestValidatorSpec.sha256_file(build_log)
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("resource_coverage")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects unknown or partial resource evidence" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      resource = File.join(fixture[:run_dir], "stage2_build.resource")
      File.write(resource, BootstrapManifestValidatorSpec.resource_row("unknown", "unknown"))
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "stage2_resource_sha256",
        BootstrapManifestValidatorSpec.sha256_file(resource)
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("resource_coverage")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects forged resource labels with inconsistent counters" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      resource = File.join(fixture[:run_dir], "stage2_build.resource")
      forged = BootstrapManifestValidatorSpec.resource_row
        .sub("max_fd=8", "max_fd=0")
        .sub("fd_samples=2", "fd_samples=1")
        .sub("fd_topology_stable_samples=2", "fd_topology_stable_samples=1")
        .sub("fd_topology_unstable_samples=0", "fd_topology_unstable_samples=1")
      File.write(resource, forged)
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "stage2_resource_sha256",
        BootstrapManifestValidatorSpec.sha256_file(resource)
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("resource_coverage")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects worker-only or non-normal build policy" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      BootstrapManifestValidatorSpec.update_manifest(fixture[:manifest], "worker_policy", "workers_4")
      BootstrapManifestValidatorSpec.update_manifest(fixture[:manifest], "stage2_build_mode", "emit_only")
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("build_policy")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects broken producer lineage" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      BootstrapManifestValidatorSpec.update_manifest(fixture[:manifest], "stage2_producer_sha256", "0" * 64)
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("producer_lineage")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects stale source or harness identity" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      BootstrapManifestValidatorSpec.update_manifest(fixture[:manifest], "source_tree_sha256_end", "0" * 64)
      BootstrapManifestValidatorSpec.update_manifest(fixture[:manifest], "harness_run_safe_sha256", "0" * 64)
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("source_or_harness_identity")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects stale shared evidence-contract identity" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "harness_evidence_contract_sha256",
        "0" * 64
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("source_or_harness_identity")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects a rehashed non-canonical plain smoke source" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      smoke_source = File.join(fixture[:run_dir], "_smoke_puts42.cr")
      File.write(smoke_source, "puts 43\n")
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "smoke_plain_source_sha256",
        BootstrapManifestValidatorSpec.sha256_file(smoke_source)
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("smoke_input_identity")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects stale no-prelude oracle identity" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      BootstrapManifestValidatorSpec.update_manifest(
        fixture[:manifest],
        "smoke_noprelude_oracle_sha256_end",
        "0" * 64
      )
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("smoke_input_identity")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects duplicate manifest fields" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      File.open(fixture[:manifest], "a") { |file| file << "status=success\n" }
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("manifest_shape")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects symlink evidence" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      build_log = File.join(fixture[:run_dir], "stage2_build.log")
      File.delete(build_log)
      File.symlink(File.join(fixture[:run_dir], "stage1_build.log"), build_log)
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("artifact_hash")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects a manifest built by a different host compiler" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    other_host = File.join(fixture[:workdir], "other-crystal")
    BootstrapManifestValidatorSpec.write_executable(other_host, "#!/bin/sh\n# other\nexit 0\n")
    begin
      mismatched = fixture.merge({host: other_host})
      result = BootstrapManifestValidatorSpec.run_validator(validator, mismatched)
      result[:status].success?.should be_false
      result[:output].should contain("host_identity")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end
  it "rejects a non-executable trusted host" do
    fixture = BootstrapManifestValidatorSpec.create_fixture(root)
    begin
      File.chmod(fixture[:host], 0o644)
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("host_identity")
    ensure
      FileUtils.rm_rf(fixture[:workdir])
    end
  end

  it "rejects a run directory inside the source evidence scope before reading a manifest" do
    workdir = File.join(Dir.tempdir, "adamas_t8_source_run_#{Process.pid}_#{Random.rand(1_000_000)}")
    run_dir = File.join(root, "src", ".t8-rejected-#{Process.pid}-#{Random.rand(1_000_000)}")
    host = File.join(workdir, "trusted-crystal")
    FileUtils.mkdir_p(workdir)
    Dir.mkdir(run_dir)
    File.chmod(run_dir, 0o700)
    BootstrapManifestValidatorSpec.write_executable(host)
    fixture = {workdir: workdir, run_dir: run_dir, host: host, manifest: File.join(run_dir, "bootstrap_chain.manifest")}
    begin
      result = BootstrapManifestValidatorSpec.run_validator(validator, fixture)
      result[:status].success?.should be_false
      result[:output].should contain("run_directory")
    ensure
      FileUtils.rm_rf(run_dir)
      FileUtils.rm_rf(workdir)
    end
  end

  it "keeps the admitted process-tree mode aligned with the B7 producer" do
    producer = File.read(File.join(root, "scripts", "run_safe.sh"))
    consumer = File.read(validator)
    producer.should contain(%(local process_tree_mode="ps_ancestry_snapshot"))
    consumer.should match(/bootstrap_resource_field process_tree_mode .*ps_ancestry_snapshot/)
  end
end
