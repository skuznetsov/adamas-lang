require "spec"
require "file_utils"

private def run_safe_resource_line(output : String) : String
  output.lines.reverse_each do |line|
    return line.chomp if line.starts_with?("[RESOURCE] ")
  end
  raise "run_safe did not emit a final [RESOURCE] line:\n#{output}"
end

private def run_safe_resource_fields(line : String) : Hash(String, String)
  fields = Hash(String, String).new
  line.split[1..].each do |entry|
    key, value = entry.split("=", 2)
    fields[key] = value
  end
  fields
end

describe "run_safe resource metrics" do
  it "emits an aggregate process-tree resource line on success" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    fake_bin = File.join(Dir.tempdir, "adamas_run_safe_metrics_#{Process.pid}_#{Random.rand(1_000_000)}")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    FileUtils.mkdir_p(fake_bin)
    File.write(File.join(fake_bin, "ps"), <<-'SH')
      #!/bin/sh
      case "$*" in
        *"-axo pid=,ppid="*)
          root="${RUN_SAFE_TARGET_PID:-${RUN_SAFE_SUPERVISOR_PID:?}}"
          child="$(cat "${FAKE_CHILD_PID_FILE:-/nonexistent}" 2>/dev/null || true)"
          printf '%s 1\n' "$root"
          [ -n "$child" ] && printf '%s %s\n' "$child" "$root"
          ;;
        *"-o pid="*) printf '%s\n' "${RUN_SAFE_SUPERVISOR_PID:?}" ;;
        *"-o rss="*) printf '10\n' ;;
        *) exit 2 ;;
      esac
    SH
    File.chmod(File.join(fake_bin, "ps"), 0o755)
    File.write(File.join(fake_bin, "lsof"), <<-'SH')
      #!/bin/sh
      pids=""
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "-p" ]; then pids="$2"; shift; fi
        shift
      done
      count=$(printf '%s\n' "$pids" | awk -F, '{print NF}')
      [ "$count" -gt 0 ] || count=1
      i=0
      while [ "$i" -lt $((count * 3)) ]; do
        printf 'f%s\n' "$i"
        i=$((i + 1))
      done
    SH
    File.chmod(File.join(fake_bin, "lsof"), 0o755)
    File.write(File.join(fake_bin, "pgrep"), <<-'SH')
      #!/bin/sh
      parent="${2:-}"
      child="$(cat "${FAKE_CHILD_PID_FILE:-/nonexistent}" 2>/dev/null || true)"
      if [ "$parent" = "${RUN_SAFE_TARGET_PID:-}" ] && [ -n "$child" ]; then
        printf '%s\n' "$child"
        exit 0
      fi
      exit 1
    SH
    File.chmod(File.join(fake_bin, "pgrep"), 0o755)
    child_pid_file = File.join(Dir.tempdir, "adamas_run_safe_child_#{Process.pid}_#{Random.rand(1_000_000)}.pid")

    begin
      status = Process.run(
        runner,
        ["/bin/sh", "3", "64", "-c", "sleep 1 & echo $! > #{Process.quote(child_pid_file)}; wait"],
        env: {
          "PATH" => "#{fake_bin}:/usr/bin:/bin",
          "FAKE_CHILD_PID_FILE" => child_pid_file,
        },
        output: stdout,
        error: stderr
      )
      output = "#{stdout}#{stderr}"
      fields = run_safe_resource_fields(run_safe_resource_line(output))

      status.success?.should be_true
      output.should contain("[EXIT: 0]")
      fields["tree_coverage"].should eq("complete"), output
      fields["rss_available"].should eq("yes"), output
      fields["fd_available"].should eq("yes"), output
      fields["max_rss_kb"].to_i.should be >= 20
      fields["max_fd"].to_i.should be >= 6
      fields["rss_samples"].to_i.should be > 0
      fields["fd_samples"].to_i.should be > 0
      fields["process_tree_mode"].should eq("pgrep")
      fields["max_tree_pids"].to_i.should be >= 2
    ensure
      File.delete(child_pid_file) if File.exists?(child_pid_file)
      FileUtils.rm_rf(fake_bin)
    end
  end

  it "reports unknown measurements when ps and lsof cannot be used" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    fake_bin = File.join(Dir.tempdir, "adamas_run_safe_metrics_unavailable_#{Process.pid}_#{Random.rand(1_000_000)}")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    FileUtils.mkdir_p(fake_bin)
    ["ps", "lsof"].each do |tool|
      path = File.join(fake_bin, tool)
      body = if tool == "lsof"
               "#!/bin/sh\nprintf 'foo\\n'\nexit 0\n"
             else
               "#!/bin/sh\nexit 127\n"
             end
      File.write(path, body)
      File.chmod(path, 0o755)
    end

    begin
      status = Process.run(
        runner,
        ["/bin/sh", "2", "64", "-c", "sleep 1"],
        env: {"PATH" => "#{fake_bin}:/usr/bin:/bin"},
        output: stdout,
        error: stderr
      )
      output = "#{stdout}#{stderr}"
      fields = run_safe_resource_fields(run_safe_resource_line(output))

      status.success?.should be_true
      fields["max_rss_kb"].should eq("unknown")
      fields["max_fd"].should eq("unknown")
      fields["rss_samples"].should eq("0")
      fields["fd_samples"].should eq("0")
      fields["rss_available"].should eq("unknown")
      fields["fd_available"].should eq("unknown")
      fields["tree_coverage"].should eq("unknown")
    ensure
      FileUtils.rm_rf(fake_bin)
    end
  end

  it "does not publish a parent-only FD count as a process-tree maximum" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    fake_bin = File.join(Dir.tempdir, "adamas_run_safe_metrics_partial_tree_#{Process.pid}_#{Random.rand(1_000_000)}")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    FileUtils.mkdir_p(fake_bin)
    File.write(File.join(fake_bin, "ps"), "#!/bin/sh\nexit 127\n")
    File.write(File.join(fake_bin, "pgrep"), "#!/bin/sh\nexit 127\n")
    File.write(File.join(fake_bin, "lsof"), "#!/bin/sh\nprintf 'f0\\nf1\\n'\n")
    %w[ps pgrep lsof].each { |tool| File.chmod(File.join(fake_bin, tool), 0o755) }

    begin
      status = Process.run(
        runner,
        ["/bin/sh", "2", "64", "-c", "sleep 1 & wait"],
        env: {"PATH" => "#{fake_bin}:/usr/bin:/bin"},
        output: stdout,
        error: stderr
      )
      fields = run_safe_resource_fields(run_safe_resource_line("#{stdout}#{stderr}"))

      status.success?.should be_true
      fields["max_fd"].should eq("unknown")
      fields["fd_available"].should eq("unknown")
      fields["process_tree_mode"].should eq("unknown")
      fields["tree_coverage"].should eq("unknown")
      fields["tree_incomplete_samples"].to_i.should be > 0
    ensure
      FileUtils.rm_rf(fake_bin)
    end
  end

  it "rejects malformed bounds before launching the target" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    marker = File.join(Dir.tempdir, "adamas_run_safe_bad_bounds_#{Process.pid}_#{Random.rand(1_000_000)}")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    begin
      status = Process.run(
        runner,
        ["/bin/sh", "not-a-timeout", "64", "-c", "touch #{Process.quote(marker)}"],
        output: stdout,
        error: stderr
      )
      status.success?.should be_false
      File.exists?(marker).should be_false
      "#{stdout}#{stderr}".should contain("timeout_sec must be a positive integer")
    ensure
      File.delete(marker) if File.exists?(marker)
    end
  end
end
