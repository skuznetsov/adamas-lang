require "spec"
require "file_utils"

describe "bootstrap stage comparison scripts" do
  it "admits the early s1_bootstrap-to-s2b semantic gate" do
    root = File.expand_path("..", __DIR__)
    script_path = File.join(root, "scripts", "compare_bootstrap_stages.sh")
    script = File.read(script_path)

    script.should contain(%(BOOTSTRAP_COMPARE_STAGE_COUNT:-5))
    script.should contain(%(compare the first N stages, 2..5))

    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run(
      script_path,
      output: stdout,
      error: stderr,
      env: {"BOOTSTRAP_COMPARE_STAGE_COUNT" => "1"}
    )

    status.exit_code.should eq(2)
    "#{stdout}#{stderr}".should contain("must be an integer from 2 through 5")
  end

  it "preserves SSA def-use differences during normalization" do
    root = File.expand_path("..", __DIR__)
    normalizer = File.join(root, "scripts", "normalize_bootstrap_ir.sh")
    workdir = File.join(Dir.tempdir, "adamas_normalize_ssa_#{Process.pid}_#{Random.rand(1_000_000)}")
    Dir.mkdir(workdir)
    left = File.join(workdir, "left.mir")
    right = File.join(workdir, "right.mir")

    begin
      File.write(left, "%1 = literal 1\n%2 = literal 2\nreturn %1\n")
      File.write(right, "%1 = literal 1\n%2 = literal 2\nreturn %2\n")

      normalized = [left, right].map do |path|
        output = IO::Memory.new
        status = Process.run(normalizer, [path], output: output)
        status.success?.should be_true
        output.to_s
      end

      normalized[0].should_not eq(normalized[1])
      normalized[0].should contain("return %1")
      normalized[1].should contain("return %2")
    ensure
      File.delete(left) if File.exists?(left)
      File.delete(right) if File.exists?(right)
      Dir.delete(workdir) if Dir.exists?(workdir)
    end
  end

  it "preserves generated callback identity and numeric constants" do
    root = File.expand_path("..", __DIR__)
    normalizer = File.join(root, "scripts", "normalize_bootstrap_ir.sh")
    input = IO::Memory.new("call @__crystal_block_proc_51\ncall @__crystal_block_proc_52\nvalue=0x10\n")
    output = IO::Memory.new

    status = Process.run(normalizer, input: input, output: output)

    status.success?.should be_true
    normalized = output.to_s
    normalized.should contain("__crystal_block_proc_51")
    normalized.should contain("__crystal_block_proc_52")
    normalized.should contain("0x10")
  end

  it "rejects stale IR artifacts when a compiler reports success without emitting" do
    root = File.expand_path("..", __DIR__)
    emitter = File.join(root, "scripts", "emit_bootstrap_ir.sh")
    workdir = File.join(Dir.tempdir, "adamas_stale_bootstrap_ir_#{Process.pid}_#{Random.rand(1_000_000)}")
    compiler = File.join(workdir, "success-without-output")
    source = File.join(workdir, "probe.cr")
    prefix = File.join(workdir, "stage")
    FileUtils.mkdir_p(workdir)

    begin
      File.write(compiler, "#!/bin/sh\nexit 0\n")
      File.chmod(compiler, 0o755)
      File.write(source, "1\n")

      {
        "hir" => "hir",
        "mir" => "mir",
        "ll"  => "ll",
      }.each do |step, extension|
        File.write("#{prefix}.#{step}.out.#{extension}", "stale internal #{step}\n")
        File.write("#{prefix}.#{step}", "stale public #{step}\n")
      end

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(emitter, [compiler, source, prefix], output: stdout, error: stderr)

      status.success?.should be_false
      "#{stdout}#{stderr}".should contain("expected hir artifact missing")
      File.exists?("#{prefix}.hir").should be_false
    ensure
      FileUtils.rm_rf(workdir)
    end
  end

  it "labels normalized textual equality as IR shape evidence" do
    root = File.expand_path("..", __DIR__)
    comparator = File.read(File.join(root, "scripts", "compare_bootstrap_stages.sh"))

    comparator.should contain("IR_SHAPE_DIFF")
    comparator.should contain("IR_SHAPE_EQ")
    comparator.should_not contain("SEMANTIC_EQ")
  end

  it "rejects a stage binary whose hash does not match the run manifest" do
    root = File.expand_path("..", __DIR__)
    comparator = File.join(root, "scripts", "compare_bootstrap_stages.sh")
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_manifest_mismatch_#{Process.pid}_#{Random.rand(1_000_000)}")
    stage_dir = File.join(workdir, "stages")
    out_dir = File.join(workdir, "ir")
    corpus = File.join(workdir, "probe.cr")
    invoked = File.join(workdir, "compiler-invoked")
    FileUtils.mkdir_p(stage_dir)

    begin
      %w[s1_bootstrap s2b].each do |stage|
        path = File.join(stage_dir, stage)
        File.write(path, "#!/bin/sh\ntouch #{Process.quote(invoked)}\nexit 0\n")
        File.chmod(path, 0o755)
      end
      File.write(corpus, "1\n")
      File.write(
        File.join(stage_dir, "bootstrap_stages.manifest"),
        [
          "status=success",
          "source_hash_consistent=1",
          "stable_manifest_run_id=test-run",
          "s1_bootstrap_sha256=#{"0" * 64}",
          "s2b_sha256=#{"0" * 64}",
          "",
        ].join('\n')
      )

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(
        comparator,
        [stage_dir, corpus, out_dir],
        env: {"BOOTSTRAP_COMPARE_STAGE_COUNT" => "2"},
        output: stdout,
        error: stderr
      )

      status.success?.should be_false
      "#{stdout}#{stderr}".should contain("stage hash does not match provenance manifest")
      File.exists?(invoked).should be_false
    ensure
      FileUtils.rm_rf(workdir)
    end
  end
end
