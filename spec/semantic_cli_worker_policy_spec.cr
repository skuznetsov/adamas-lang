require "./semantic_cli_helpers"

include SemanticCliSpecHelpers

describe "CLI LLVM worker policy" do
  it "optimizes MIR on the serial CLI path when workers are unset" do
    previous_workers = ENV["ADAMAS_LLVM_WORKERS"]?
    previous_stop = ENV["ADAMAS_STOP_AFTER_MIR_OPT"]?
    ENV.delete("ADAMAS_LLVM_WORKERS")
    ENV["ADAMAS_STOP_AFTER_MIR_OPT"] = "1"

    begin
      with_temp_shadow_project({"main.cr" => "1\n"}) do |dir|
        main_path = File.join(dir, "main.cr")
        output_path = File.join(dir, "main")
        out_io = IO::Memory.new
        err_io = IO::Memory.new

        status = Adamas::Compiler::CLI.new([
          main_path,
          "--no-prelude",
          "--stats",
          "--verbose",
          "--no-link",
          "-o",
          output_path,
        ]).run(out_io: out_io, err_io: err_io)

        status.should eq(0)
        out_io.to_s.should contain("Optimizing MIR (serial)...")
        out_io.to_s.should_not contain("MIR optimization deferred to LLVM workers")
        err_io.to_s.should be_empty
      end
    ensure
      if previous_workers
        ENV["ADAMAS_LLVM_WORKERS"] = previous_workers
      else
        ENV.delete("ADAMAS_LLVM_WORKERS")
      end
      if previous_stop
        ENV["ADAMAS_STOP_AFTER_MIR_OPT"] = previous_stop
      else
        ENV.delete("ADAMAS_STOP_AFTER_MIR_OPT")
      end
    end
  end

  it "keeps invalid overrides serial and defers only for explicit parallel workers" do
    previous_workers = ENV["ADAMAS_LLVM_WORKERS"]?
    previous_stop = ENV["ADAMAS_STOP_AFTER_MIR_OPT"]?
    ENV["ADAMAS_STOP_AFTER_MIR_OPT"] = "1"

    begin
      {
        {"not-an-int", false},
        {"0", false},
        {"-4", false},
        {"4", true},
      }.each do |value, parallel|
        ENV["ADAMAS_LLVM_WORKERS"] = value
        with_temp_shadow_project({"main.cr" => "1\n"}) do |dir|
          main_path = File.join(dir, "main.cr")
          output_path = File.join(dir, "main")
          out_io = IO::Memory.new
          err_io = IO::Memory.new

          status = Adamas::Compiler::CLI.new([
            main_path,
            "--no-prelude",
            "--stats",
            "--verbose",
            "--no-link",
            "-o",
            output_path,
          ]).run(out_io: out_io, err_io: err_io)

          status.should eq(0)
          if parallel
            out_io.to_s.should contain("MIR optimization deferred to LLVM workers (parallel)")
            out_io.to_s.should_not contain("Optimizing MIR (serial)...")
          else
            out_io.to_s.should contain("Optimizing MIR (serial)...")
            out_io.to_s.should_not contain("MIR optimization deferred to LLVM workers")
          end
          err_io.to_s.should be_empty
        end
      end
    ensure
      if previous_workers
        ENV["ADAMAS_LLVM_WORKERS"] = previous_workers
      else
        ENV.delete("ADAMAS_LLVM_WORKERS")
      end
      if previous_stop
        ENV["ADAMAS_STOP_AFTER_MIR_OPT"] = previous_stop
      else
        ENV.delete("ADAMAS_STOP_AFTER_MIR_OPT")
      end
    end
  end
end
