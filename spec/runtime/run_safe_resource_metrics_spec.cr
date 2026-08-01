require "spec"
require "file_utils"

private def run_safe_resource_line(path : String) : String
  lines = File.read(path).lines.map(&.chomp)
  unless lines.size == 1 && lines[0].starts_with?("[RUN_SAFE_RESOURCE] ")
    raise "run_safe evidence file must contain exactly one owned resource row: #{lines.inspect}"
  end
  lines[0]
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
    resource_file = File.join(Dir.tempdir, "adamas_run_safe_resource_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    FileUtils.mkdir_p(fake_bin)
    File.write(File.join(fake_bin, "ps"), <<-'SH')
      #!/bin/sh
      case "$*" in
        *"-axo pid=,ppid=,pgid=,rss="*)
          root="${RUN_SAFE_TARGET_PID:-${RUN_SAFE_SUPERVISOR_PID:?}}"
          child="$(cat "${FAKE_CHILD_PID_FILE:-/nonexistent}" 2>/dev/null || true)"
          printf '%s 1 %s 10\n' "$root" "$root"
          [ -n "$child" ] && printf '%s %s %s 10\n' "$child" "$root" "$root"
          exit 0
          ;;
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
      old_ifs="$IFS"
      IFS=,
      for pid in $pids; do
        printf 'p%s\n' "$pid"
        printf 'f0\nf1\nf2\n'
      done
      IFS="$old_ifs"
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
          "RUN_SAFE_RESOURCE_FILE" => resource_file,
        },
        output: stdout,
        error: stderr
      )
      output = "#{stdout}#{stderr}"
      fields = run_safe_resource_fields(run_safe_resource_line(resource_file))

      status.success?.should be_true
      output.should contain("[EXIT: 0]")
      fields["tree_coverage"].should eq("all_scheduled_snapshots"), output
      fields["fd_tree_coverage"].should eq("all_stable_pairs"), output
      fields["rss_available"].should eq("yes"), output
      fields["fd_available"].should eq("yes"), output
      fields["max_rss_kb"].to_i.should be >= 20
      fields["max_fd"].to_i.should be >= 6
      fields["rss_samples"].to_i.should be > 0
      fields["fd_samples"].to_i.should be > 0
      fields["process_tree_mode"].should eq("ps_ancestry_snapshot")
      fields["max_tree_pids"].to_i.should be >= 2
    ensure
      File.delete(child_pid_file) if File.exists?(child_pid_file)
      File.delete(resource_file) if File.exists?(resource_file)
      FileUtils.rm_rf(fake_bin)
    end
  end

  it "reports unknown measurements when ps and lsof cannot be used" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    fake_bin = File.join(Dir.tempdir, "adamas_run_safe_metrics_unavailable_#{Process.pid}_#{Random.rand(1_000_000)}")
    resource_file = File.join(Dir.tempdir, "adamas_run_safe_resource_unavailable_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
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
        env: {
          "PATH" => "#{fake_bin}:/usr/bin:/bin",
          "RUN_SAFE_RESOURCE_FILE" => resource_file,
        },
        output: stdout,
        error: stderr
      )
      output = "#{stdout}#{stderr}"
      fields = run_safe_resource_fields(run_safe_resource_line(resource_file))

      status.success?.should be_true
      fields["max_rss_kb"].should eq("unknown")
      fields["max_fd"].should eq("unknown")
      fields["rss_samples"].should eq("0")
      fields["fd_samples"].should eq("0")
      fields["rss_available"].should eq("unknown")
      fields["fd_available"].should eq("unknown")
      fields["tree_coverage"].should eq("unknown")
    ensure
      File.delete(resource_file) if File.exists?(resource_file)
      FileUtils.rm_rf(fake_bin)
    end
  end

  it "does not publish FD data when rooted-ancestry observation is unavailable" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    fake_bin = File.join(Dir.tempdir, "adamas_run_safe_metrics_partial_tree_#{Process.pid}_#{Random.rand(1_000_000)}")
    resource_file = File.join(Dir.tempdir, "adamas_run_safe_resource_partial_tree_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
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
        env: {
          "PATH" => "#{fake_bin}:/usr/bin:/bin",
          "RUN_SAFE_RESOURCE_FILE" => resource_file,
        },
        output: stdout,
        error: stderr
      )
      fields = run_safe_resource_fields(run_safe_resource_line(resource_file))

      status.success?.should be_true
      fields["max_fd"].should eq("unknown")
      fields["fd_available"].should eq("unknown")
      fields["process_tree_mode"].should eq("unknown")
      fields["tree_coverage"].should eq("unknown")
      fields["fd_topology_unstable_samples"].to_i.should be > 0
    ensure
      File.delete(resource_file) if File.exists?(resource_file)
      FileUtils.rm_rf(fake_bin)
    end
  end

  it "rejects a malformed ps snapshot instead of certifying a numeric tree maximum" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    fake_bin = File.join(Dir.tempdir, "adamas_run_safe_metrics_bad_ps_#{Process.pid}_#{Random.rand(1_000_000)}")
    resource_file = File.join(Dir.tempdir, "adamas_run_safe_resource_bad_ps_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    FileUtils.mkdir_p(fake_bin)
    File.write(File.join(fake_bin, "ps"), <<-'SH')
      #!/bin/sh
      root="${RUN_SAFE_TARGET_PID:-${RUN_SAFE_SUPERVISOR_PID:?}}"
      printf '%s 1 %s 10\n' "$root" "$root"
      [ -n "${RUN_SAFE_TARGET_PID:-}" ] && printf 'truncated row\n'
      exit 0
    SH
    File.write(File.join(fake_bin, "lsof"), <<-'SH')
      #!/bin/sh
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "-p" ]; then printf 'p%s\nf0\n' "$2"; exit 0; fi
        shift
      done
      exit 2
    SH
    %w[ps lsof].each { |tool| File.chmod(File.join(fake_bin, tool), 0o755) }

    begin
      status = Process.run(
        runner,
        ["/bin/sh", "2", "64", "-c", "sleep 1"],
        env: {
          "PATH" => "#{fake_bin}:/usr/bin:/bin",
          "RUN_SAFE_RESOURCE_FILE" => resource_file,
        },
        output: stdout,
        error: stderr
      )
      fields = run_safe_resource_fields(run_safe_resource_line(resource_file))

      status.success?.should be_true
      fields["max_rss_kb"].should eq("unknown")
      fields["max_fd"].should eq("unknown")
      fields["tree_coverage"].should eq("unknown")
      fields["fd_topology_unstable_samples"].to_i.should be > 0
    ensure
      File.delete(resource_file) if File.exists?(resource_file)
      FileUtils.rm_rf(fake_bin)
    end
  end

  it "rejects partial lsof PID coverage while retaining stable RSS evidence" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    fake_bin = File.join(Dir.tempdir, "adamas_run_safe_metrics_partial_lsof_#{Process.pid}_#{Random.rand(1_000_000)}")
    resource_file = File.join(Dir.tempdir, "adamas_run_safe_resource_partial_lsof_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
    child_pid_file = File.join(Dir.tempdir, "adamas_run_safe_partial_lsof_child_#{Process.pid}_#{Random.rand(1_000_000)}.pid")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    FileUtils.mkdir_p(fake_bin)
    File.write(File.join(fake_bin, "ps"), <<-'SH')
      #!/bin/sh
      root="${RUN_SAFE_TARGET_PID:-${RUN_SAFE_SUPERVISOR_PID:?}}"
      child="$(cat "${FAKE_CHILD_PID_FILE:-/nonexistent}" 2>/dev/null || true)"
      printf '%s 1 %s 10\n' "$root" "$root"
      [ -n "$child" ] && printf '%s %s %s 10\n' "$child" "$root" "$root"
      exit 0
    SH
    File.write(File.join(fake_bin, "lsof"), <<-'SH')
      #!/bin/sh
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "-p" ]; then
          first="${2%%,*}"
          printf 'p%s\nf0\n' "$first"
          exit 0
        fi
        shift
      done
      exit 2
    SH
    %w[ps lsof].each { |tool| File.chmod(File.join(fake_bin, tool), 0o755) }

    begin
      status = Process.run(
        runner,
        ["/bin/sh", "3", "64", "-c", "sleep 1 & echo $! > #{Process.quote(child_pid_file)}; wait"],
        env: {
          "PATH" => "#{fake_bin}:/usr/bin:/bin",
          "FAKE_CHILD_PID_FILE" => child_pid_file,
          "RUN_SAFE_RESOURCE_FILE" => resource_file,
        },
        output: stdout,
        error: stderr
      )
      fields = run_safe_resource_fields(run_safe_resource_line(resource_file))

      status.success?.should be_true
      fields["tree_coverage"].should eq("all_scheduled_snapshots")
      fields["fd_tree_coverage"].should eq("unknown")
      fields["max_rss_kb"].to_i.should be >= 20
      fields["rss_available"].should eq("yes")
      fields["max_fd"].should eq("unknown")
      fields["fd_available"].should eq("unknown")
      fields["fd_samples"].should eq("0")
    ensure
      File.delete(child_pid_file) if File.exists?(child_pid_file)
      File.delete(resource_file) if File.exists?(resource_file)
      FileUtils.rm_rf(fake_bin)
    end
  end

  it "rejects empty and malformed lsof FD fields" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    fake_bin = File.join(Dir.tempdir, "adamas_run_safe_metrics_bad_lsof_#{Process.pid}_#{Random.rand(1_000_000)}")

    FileUtils.mkdir_p(fake_bin)
    File.write(File.join(fake_bin, "ps"), <<-'SH')
      #!/bin/sh
      root="${RUN_SAFE_TARGET_PID:-${RUN_SAFE_SUPERVISOR_PID:?}}"
      printf '%s 1 %s 10\n' "$root" "$root"
    SH
    File.chmod(File.join(fake_bin, "ps"), 0o755)

    begin
      {"empty" => "", "malformed" => "foo"}.each do |case_name, fd_field|
        resource_file = File.join(Dir.tempdir, "adamas_run_safe_resource_#{case_name}_lsof_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        field_command = fd_field.empty? ? "" : "printf '#{fd_field}\\n'"
        File.write(File.join(fake_bin, "lsof"), <<-SH)
          #!/bin/sh
          while [ "$#" -gt 0 ]; do
            if [ "$1" = "-p" ]; then
              printf 'p%s\\n' "$2"
              #{field_command}
              exit 0
            fi
            shift
          done
          exit 2
        SH
        File.chmod(File.join(fake_bin, "lsof"), 0o755)

        begin
          status = Process.run(
            runner,
            ["/bin/sh", "2", "64", "-c", "sleep 1"],
            env: {
              "PATH" => "#{fake_bin}:/usr/bin:/bin",
              "RUN_SAFE_RESOURCE_FILE" => resource_file,
            },
            output: stdout,
            error: stderr
          )
          fields = run_safe_resource_fields(run_safe_resource_line(resource_file))

          status.success?.should be_true
          fields["max_rss_kb"].to_i.should be > 0
          fields["max_fd"].should eq("unknown"), case_name
          fields["fd_available"].should eq("unknown"), case_name
          fields["fd_samples"].should eq("0"), case_name
        ensure
          File.delete(resource_file) if File.exists?(resource_file)
        end
      end
    ensure
      FileUtils.rm_rf(fake_bin)
    end
  end

  it "keeps RSS point samples but rejects FD aggregation across topology churn" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    fake_bin = File.join(Dir.tempdir, "adamas_run_safe_metrics_tree_churn_#{Process.pid}_#{Random.rand(1_000_000)}")
    resource_file = File.join(Dir.tempdir, "adamas_run_safe_resource_tree_churn_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
    counter_file = File.join(Dir.tempdir, "adamas_run_safe_tree_churn_count_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    FileUtils.mkdir_p(fake_bin)
    File.write(File.join(fake_bin, "ps"), <<-'SH')
      #!/bin/sh
      count="$(cat "${FAKE_PS_COUNTER:?}" 2>/dev/null || printf '0')"
      count=$((count + 1))
      printf '%s\n' "$count" >"${FAKE_PS_COUNTER:?}"
      root="${RUN_SAFE_TARGET_PID:-${RUN_SAFE_SUPERVISOR_PID:?}}"
      printf '%s 1 %s 10\n' "$root" "$root"
      if [ -n "${RUN_SAFE_TARGET_PID:-}" ] && [ $((count % 2)) -eq 0 ]; then
        printf '999999 %s %s 10\n' "$root" "$root"
      fi
      exit 0
    SH
    File.write(File.join(fake_bin, "lsof"), <<-'SH')
      #!/bin/sh
      pids=""
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "-p" ]; then pids="$2"; shift; fi
        shift
      done
      old_ifs="$IFS"
      IFS=,
      for pid in $pids; do printf 'p%s\nf0\n' "$pid"; done
      IFS="$old_ifs"
    SH
    %w[ps lsof].each { |tool| File.chmod(File.join(fake_bin, tool), 0o755) }

    begin
      status = Process.run(
        runner,
        ["/bin/sh", "2", "64", "-c", "sleep 1"],
        env: {
          "PATH" => "#{fake_bin}:/usr/bin:/bin",
          "FAKE_PS_COUNTER" => counter_file,
          "RUN_SAFE_RESOURCE_FILE" => resource_file,
        },
        output: stdout,
        error: stderr
      )
      fields = run_safe_resource_fields(run_safe_resource_line(resource_file))

      status.success?.should be_true
      fields["tree_coverage"].should eq("all_scheduled_snapshots")
      fields["max_rss_kb"].to_i.should be >= 20
      fields["fd_tree_coverage"].should eq("unknown")
      fields["max_fd"].should eq("unknown")
      fields["fd_topology_unstable_samples"].to_i.should be > 0
    ensure
      File.delete(counter_file) if File.exists?(counter_file)
      File.delete(resource_file) if File.exists?(resource_file)
      FileUtils.rm_rf(fake_bin)
    end
  end

  it "keeps a valid RSS point sample but rejects FD when its topology fence is malformed" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    fake_bin = File.join(Dir.tempdir, "adamas_run_safe_metrics_bad_fence_#{Process.pid}_#{Random.rand(1_000_000)}")
    resource_file = File.join(Dir.tempdir, "adamas_run_safe_resource_bad_fence_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
    counter_file = File.join(Dir.tempdir, "adamas_run_safe_bad_fence_count_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    FileUtils.mkdir_p(fake_bin)
    File.write(File.join(fake_bin, "ps"), <<-'SH')
      #!/bin/sh
      count="$(cat "${FAKE_PS_COUNTER:?}" 2>/dev/null || printf '0')"
      count=$((count + 1))
      printf '%s\n' "$count" >"${FAKE_PS_COUNTER:?}"
      root="${RUN_SAFE_TARGET_PID:-${RUN_SAFE_SUPERVISOR_PID:?}}"
      printf '%s 1 %s 10\n' "$root" "$root"
      if [ -n "${RUN_SAFE_TARGET_PID:-}" ] && [ $((count % 2)) -eq 1 ]; then
        printf 'malformed topology fence\n'
      fi
      exit 0
    SH
    File.write(File.join(fake_bin, "lsof"), <<-'SH')
      #!/bin/sh
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "-p" ]; then printf 'p%s\nf0\n' "$2"; exit 0; fi
        shift
      done
      exit 2
    SH
    %w[ps lsof].each { |tool| File.chmod(File.join(fake_bin, tool), 0o755) }

    begin
      status = Process.run(
        runner,
        ["/bin/sh", "2", "64", "-c", "sleep 1"],
        env: {
          "PATH" => "#{fake_bin}:/usr/bin:/bin",
          "FAKE_PS_COUNTER" => counter_file,
          "RUN_SAFE_RESOURCE_FILE" => resource_file,
        },
        output: stdout,
        error: stderr
      )
      fields = run_safe_resource_fields(run_safe_resource_line(resource_file))

      status.success?.should be_true
      fields["max_rss_kb"].to_i.should be > 0
      fields["tree_coverage"].should eq("all_scheduled_snapshots")
      fields["max_fd"].should eq("unknown")
      fields["fd_tree_coverage"].should eq("unknown")
      fields["fd_topology_unstable_samples"].to_i.should be > 0
    ensure
      File.delete(counter_file) if File.exists?(counter_file)
      File.delete(resource_file) if File.exists?(resource_file)
      FileUtils.rm_rf(fake_bin)
    end
  end

  it "keeps target marker text outside the producer-owned evidence channel" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    resource_file = File.join(Dir.tempdir, "adamas_run_safe_resource_spoof_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    begin
      status = Process.run(
        runner,
        ["/bin/sh", "2", "64", "-c", "printf '[RUN_SAFE_RESOURCE] schema=fake outcome=success\\n'"],
        env: {"RUN_SAFE_RESOURCE_FILE" => resource_file},
        output: stdout,
        error: stderr
      )
      owned_line = run_safe_resource_line(resource_file)

      status.success?.should be_true
      owned_line.should contain("schema=run_safe_resource_v1")
      owned_line.should_not contain("schema=fake")
      "#{stdout}#{stderr}".should contain("schema=fake")
    ensure
      File.delete(resource_file) if File.exists?(resource_file)
    end
  end

  it "refuses to overwrite a pre-existing evidence path before target launch" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    resource_file = File.join(Dir.tempdir, "adamas_run_safe_resource_existing_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
    marker = File.join(Dir.tempdir, "adamas_run_safe_existing_path_target_#{Process.pid}_#{Random.rand(1_000_000)}")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    begin
      File.write(resource_file, "owned-before-run\n")
      status = Process.run(
        runner,
        ["/bin/sh", "2", "64", "-c", "touch #{Process.quote(marker)}"],
        env: {"RUN_SAFE_RESOURCE_FILE" => resource_file},
        output: stdout,
        error: stderr
      )

      status.success?.should be_false
      File.read(resource_file).should eq("owned-before-run\n")
      File.exists?(marker).should be_false
      "#{stdout}#{stderr}".should contain("RUN_SAFE_RESOURCE_FILE already exists")
    ensure
      File.delete(marker) if File.exists?(marker)
      File.delete(resource_file) if File.exists?(resource_file)
    end
  end

  it "fails the wrapper if the destination appears before atomic publication" do
    root = File.expand_path("../..", __DIR__)
    runner = File.join(root, "scripts", "run_safe.sh")
    resource_file = File.join(Dir.tempdir, "adamas_run_safe_resource_race_#{Process.pid}_#{Random.rand(1_000_000)}.txt")
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    begin
      status = Process.run(
        runner,
        [
          "/bin/sh",
          "2",
          "64",
          "-c",
          "printf 'target-owned\\n' > #{Process.quote(resource_file)}",
        ],
        env: {"RUN_SAFE_RESOURCE_FILE" => resource_file},
        output: stdout,
        error: stderr
      )

      status.exit_code.should eq(2)
      File.read(resource_file).should eq("target-owned\n")
      "#{stdout}#{stderr}".should contain("[RUN_SAFE_EVIDENCE_ERROR]")
    ensure
      File.delete(resource_file) if File.exists?(resource_file)
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
