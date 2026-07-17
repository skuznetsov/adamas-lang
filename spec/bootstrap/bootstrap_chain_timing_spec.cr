require "../spec_helper"
require "file_utils"

describe "bootstrap chain timing" do
  it "uses portable time output that preserves a successful child status" do
    root = File.expand_path("../..", __DIR__)
    script = File.read(File.join(root, "scripts", "bootstrap_chain.sh"))

    script.should_not contain("/usr/bin/time -l")
    script.scan("/usr/bin/time -p").size.should be >= 3

    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run("/usr/bin/time", ["-p", "true"], output: stdout, error: stderr)

    status.success?.should be_true
    stderr.to_s.should contain("real ")
    stderr.to_s.should_not contain("kern.clockrate")
  end

  it "executes both smoke binaries at every built stage" do
    root = File.expand_path("../..", __DIR__)
    workdir = File.join(Dir.tempdir, "adamas_bootstrap_chain_spec_#{Process.pid}_#{Random.rand(1_000_000)}")
    outdir = File.join(workdir, "out")
    fake_compiler = File.join(workdir, "fake-compiler")
    plain_marker = File.join(workdir, "plain-ran")
    no_prelude_marker = File.join(workdir, "no-prelude-ran")
    FileUtils.mkdir_p(workdir)

    begin
      File.write(fake_compiler, <<-SH)
        #!/bin/sh
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
        case "$source" in
          */src/adamas.cr|src/adamas.cr)
            cp "$0" "$out"
            ;;
          */_smoke_puts42.cr)
            printf '#!/bin/sh\nprintf "plain-ran\\n" >> "#{plain_marker}"\nprintf "42\\n"\n' > "$out"
            ;;
          */test_no_prelude_interpolation.cr)
            # Match the exact canonical no-prelude interpolation stdout.
            case "${FAKE_BOOTSTRAP_SMOKE_MODE:-good}" in
              missing)
                printf '#!/bin/sh\nprintf "hello world\\nn=42\\n"\n' > "$out"
                ;;
              duplicate)
                printf '#!/bin/sh\nprintf "hello world\\nnoprelude_interp_ok\\nnoprelude_interp_ok\\n"\n' > "$out"
                ;;
              *)
                printf '#!/bin/sh\nprintf "no-prelude-ran\\n" >> "#{no_prelude_marker}"\nprintf "hello world\\nn=42\\nnoprelude_interp_ok\\n"\n' > "$out"
                ;;
            esac
            ;;
          *)
            exit 3
            ;;
        esac
        chmod +x "$out"
      SH
      File.chmod(fake_compiler, 0o755)

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(
        File.join(root, "scripts", "bootstrap_chain.sh"),
        ["--stages", "2", "--host", fake_compiler, "--out", outdir, "--timeout", "10", "--mem", "256"],
        output: stdout,
        error: stderr
      )

      status.success?.should be_true, "#{stdout}\n#{stderr}"
      File.read_lines(plain_marker).should eq(["plain-ran", "plain-ran"])
      File.read_lines(no_prelude_marker).should eq(["no-prelude-ran", "no-prelude-ran"])
    ensure
      FileUtils.rm_rf(workdir)
    end
  end

  it "rejects missing, duplicate, and semantically wrong no-prelude output" do
    root = File.expand_path("../..", __DIR__)
    %w[missing duplicate wrong].each do |mode|
      workdir = File.join(Dir.tempdir, "adamas_bootstrap_chain_marker_#{mode}_#{Process.pid}_#{Random.rand(1_000_000)}")
      outdir = File.join(workdir, "out")
      fake_compiler = File.join(workdir, "fake-compiler")
      FileUtils.mkdir_p(workdir)

      begin
        File.write(fake_compiler, <<-SH)
          #!/bin/sh
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
          case "$source" in
            */src/adamas.cr|src/adamas.cr)
              cp "$0" "$out"
              ;;
            */_smoke_puts42.cr)
              printf '#!/bin/sh\nprintf "42\\n"\n' > "$out"
              ;;
            */test_no_prelude_interpolation.cr)
              case "${FAKE_BOOTSTRAP_SMOKE_MODE:-good}" in
                missing)
                  printf '#!/bin/sh\nprintf "hello world\\nn=42\\n"\n' > "$out"
                  ;;
                duplicate)
                  printf '#!/bin/sh\nprintf "hello world\\nnoprelude_interp_ok\\nnoprelude_interp_ok\\n"\n' > "$out"
                  ;;
                wrong)
                  printf '#!/bin/sh\nprintf "hello wrong\\nn=0\\nnoprelude_interp_ok\\n"\n' > "$out"
                  ;;
              esac
              ;;
            *)
              exit 3
              ;;
          esac
          chmod +x "$out"
        SH
        File.chmod(fake_compiler, 0o755)

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Process.run(
          File.join(root, "scripts", "bootstrap_chain.sh"),
          ["--stages", "1", "--host", fake_compiler, "--out", outdir, "--timeout", "10", "--mem", "256"],
          env: {"FAKE_BOOTSTRAP_SMOKE_MODE" => mode},
          output: stdout,
          error: stderr
        )

        status.success?.should be_false
        combined = "#{stdout}#{stderr}"
        expected_signal = case mode
                          when "missing"   then "marker_count=0"
                          when "duplicate" then "marker_count=2"
                          else                  "stdout_match=no"
                          end
        combined.should contain(expected_signal)
      ensure
        FileUtils.rm_rf(workdir)
      end
    end
  end
end
