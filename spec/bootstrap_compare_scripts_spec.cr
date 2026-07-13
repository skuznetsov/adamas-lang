require "spec"

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
end
