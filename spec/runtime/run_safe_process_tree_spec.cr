require "../spec_helper"

private def wait_until_process_exits(pid : Int32, timeout = 2.seconds) : Bool
  deadline = Time.instant + timeout
  while Process.exists?(pid) && Time.instant < deadline
    sleep 20.milliseconds
  end
  !Process.exists?(pid)
end

describe "run_safe process-tree cleanup" do
  it "does not leave the watchdog sleep holding a captured caller pipe" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    started_at = Time.instant

    status = Process.run(
      runner,
      ["/usr/bin/true", "20", "64"],
      output: stdout,
      error: stderr
    )

    elapsed = Time.instant - started_at
    status.success?.should be_true
    elapsed.should be < 5.seconds
    "#{stdout}#{stderr}".should contain("[EXIT: 0]")
  end

  it "kills descendants when the supervised parent times out" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    pid_file = File.join(Dir.tempdir, "adamas_run_safe_tree_#{Process.pid}_#{Random.rand(1_000_000)}.pid")
    child_pid : Int32? = nil
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    begin
      status = Process.run(
        runner,
        [
          "/bin/sh",
          "1",
          "64",
          "-c",
          "sleep 37 & echo $! > #{Process.quote(pid_file)}; wait",
        ],
        output: stdout,
        error: stderr
      )

      status.success?.should be_false
      File.exists?(pid_file).should be_true
      child_pid = File.read(pid_file).strip.to_i
      wait_until_process_exits(child_pid).should be_true
      "#{stdout}#{stderr}".should contain("[KILL] Timeout after 1s")
    ensure
      if pid = child_pid
        Process.signal(Signal::KILL, pid) if Process.exists?(pid)
      end
      File.delete(pid_file) if File.exists?(pid_file)
    end
  end

  it "kills a TERM-ignoring parent and its live child without leaving an orphan" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    pid_file = File.join(Dir.tempdir, "adamas_run_safe_term_ignore_#{Process.pid}_#{Random.rand(1_000_000)}.pid")
    child_pid : Int32? = nil
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    begin
      status = Process.run(
        runner,
        [
          "/bin/sh",
          "1",
          "64",
          "-c",
          "trap '' TERM; sleep 37 & echo $! > #{Process.quote(pid_file)}; wait",
        ],
        output: stdout,
        error: stderr
      )

      status.success?.should be_false
      File.exists?(pid_file).should be_true
      child_pid = File.read(pid_file).strip.to_i
      wait_until_process_exits(child_pid).should be_true
      "#{stdout}#{stderr}".should contain("[KILL] Timeout after 1s")
      "#{stdout}#{stderr}".should contain("[RESOURCE]")
    ensure
      if pid = child_pid
        Process.signal(Signal::KILL, pid) if Process.exists?(pid)
      end
      File.delete(pid_file) if File.exists?(pid_file)
    end
  end

  it "recursively cleans nested supervisor process groups" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    pid_file = File.join(Dir.tempdir, "adamas_nested_run_safe_#{Process.pid}_#{Random.rand(1_000_000)}.pid")
    child_pid : Int32? = nil
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    begin
      status = Process.run(
        runner,
        [
          runner,
          "1",
          "128",
          "/bin/sh",
          "40",
          "128",
          "-c",
          "sleep 43 & echo $! > #{Process.quote(pid_file)}; wait",
        ],
        output: stdout,
        error: stderr
      )

      status.success?.should be_false
      File.exists?(pid_file).should be_true
      child_pid = File.read(pid_file).strip.to_i
      wait_until_process_exits(child_pid).should be_true
      "#{stdout}#{stderr}".should contain("[KILL] Timeout after 1s")
    ensure
      if pid = child_pid
        Process.signal(Signal::KILL, pid) if Process.exists?(pid)
      end
      File.delete(pid_file) if File.exists?(pid_file)
    end
  end

  it "reaps background descendants after a successful parent exit" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    pid_file = File.join(Dir.tempdir, "adamas_success_tree_#{Process.pid}_#{Random.rand(1_000_000)}.pid")
    child_pid : Int32? = nil
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    begin
      status = Process.run(
        runner,
        [
          "/bin/sh",
          "5",
          "128",
          "-c",
          "sleep 53 & echo $! > #{Process.quote(pid_file)}; exit 0",
        ],
        output: stdout,
        error: stderr
      )

      status.success?.should be_true
      File.exists?(pid_file).should be_true
      child_pid = File.read(pid_file).strip.to_i
      wait_until_process_exits(child_pid).should be_true
      "#{stdout}#{stderr}".should contain("[EXIT: 0]")
    ensure
      if pid = child_pid
        Process.signal(Signal::KILL, pid) if Process.exists?(pid)
      end
      File.delete(pid_file) if File.exists?(pid_file)
    end
  end
end
