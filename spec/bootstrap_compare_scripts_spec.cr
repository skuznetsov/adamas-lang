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

      %w[hir mir ll].each do |step|
        File.write("#{prefix}.#{step}.out.#{step}", "stale internal #{step}\n")
        File.write("#{prefix}.#{step}", "stale public #{step}\n")
      end

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(emitter, [compiler, source, prefix], output: stdout, error: stderr)

      status.success?.should be_false
      "#{stdout}#{stderr}".should contain("expected hir artifact missing")
      %w[hir mir ll].each do |kind|
        File.exists?("#{prefix}.#{kind}").should be_false
      end
    ensure
      FileUtils.rm_rf(workdir)
    end
  end

  it "publishes three fresh artifacts and passes the requested flags exactly once" do
    emitter = File.expand_path("../scripts/emit_bootstrap_ir.sh", __DIR__)
    work = File.join(Dir.tempdir, "adamas_emit_fresh_#{Process.pid}_#{Random.rand(1_000_000)}")
    Dir.mkdir(work)
    begin
      compiler = File.join(work, "compiler")
      source = File.join(work, "source.cr")
      prefix = File.join(work, "stage")
      File.write(source, "1\n")
      File.write(compiler, <<-'SH')
        #!/bin/sh
        set -eu
        [ "$#" -eq 8 ]
        [ "$2" = "--no-prelude" ]
        [ "$3" = "--no-link" ]
        [ "$4" = "--emit" ]
        [ "$6" = "-o" ]
        [ "$8" = "--no-ast-cache" ]
        case "$5" in
          hir|mir) kind=$5 ;;
          llvm-ir) kind=ll ;;
          *) exit 1 ;;
        esac
        if [ -f "$1.partial" ] && [ "$kind" = "mir" ]; then exit 0; fi
        printf "%s\n" "$kind" > "$7.$kind"
        SH
      File.chmod(compiler, 0o755)
      stderr = IO::Memory.new
      Process.run(emitter, [compiler, source, prefix, "--no-ast-cache"], error: stderr).success?.should be_true
      %w[hir mir ll].each { |kind| File.read("#{prefix}.#{kind}").should eq("#{kind}\n") }

      Dir.mkdir("#{prefix}.emit.lock")
      Process.run(emitter, [compiler, source, prefix, "--no-ast-cache"], error: stderr).success?.should be_false
      %w[hir mir ll].each { |kind| File.read("#{prefix}.#{kind}").should eq("#{kind}\n") }
      Dir.delete("#{prefix}.emit.lock")

      File.write("#{source}.partial", "")
      Process.run(emitter, [compiler, source, prefix, "--no-ast-cache"], error: stderr).success?.should be_false
      stderr.to_s.should contain("expected mir artifact missing")
      %w[hir mir ll].each { |kind| File.exists?("#{prefix}.#{kind}").should be_false }
    ensure
      FileUtils.rm_rf(work)
    end
  end
end
