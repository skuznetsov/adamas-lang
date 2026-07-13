require "../spec_helper"
require "../../src/compiler/mir/mir"
require "../../src/compiler/mir/hir_to_mir"
require "../../src/compiler/mir/optimizations"
require "../../src/compiler/mir/llvm_backend"

class ParallelEmissionRollbackProbeGenerator < Adamas::MIR::LLVMIRGenerator
  @@parent_failure_triggered = false
  @parent_pid : Int64

  def self.reset_parent_failure_trigger
    @@parent_failure_triggered = false
  end

  def called_function?(name : String) : Bool
    @called_crystal_functions.has_key?(name)
  end

  def singleton_global?(type_ref : Adamas::MIR::TypeRef) : Bool
    @module_singleton_globals.has_key?(type_ref)
  end

  def configured_parallel_workers : Int32
    parallel_llvm_workers
  end

  def initialize(mod : Adamas::MIR::Module)
    super(mod)
    @parent_pid = Process.pid
  end

  private def emit_function(func : Adamas::MIR::Function)
    if Process.pid == @parent_pid && func.name == "force_parent_failure" && !@@parent_failure_triggered
      @@parent_failure_triggered = true
      raise "forced parent emission failure"
    end
    if Process.pid != @parent_pid
      case func.name
      when "force_worker_failure"
        LibC._exit(1)
      when "force_worker_signal_failure"
        LibC.kill(Process.pid, 9)
        LibC._exit(1)
      when "force_worker_index_error"
        raise IndexError.new("forced worker index error")
      when "force_worker_missing_artifact"
        LibC._exit(0)
      when "force_worker_hang"
        while true
        end
      end
    end
    super
  end

end

def with_parallel_workers
  previous = ENV["ADAMAS_LLVM_WORKERS"]?
  ENV["ADAMAS_LLVM_WORKERS"] = "4"
  begin
    yield
  ensure
    if previous
      ENV["ADAMAS_LLVM_WORKERS"] = previous
    else
      ENV.delete("ADAMAS_LLVM_WORKERS")
    end
  end
end

def with_worker_env(value : String?, &)
  previous = ENV["ADAMAS_LLVM_WORKERS"]?
  if value
    ENV["ADAMAS_LLVM_WORKERS"] = value
  else
    ENV.delete("ADAMAS_LLVM_WORKERS")
  end
  begin
    yield
  ensure
    if previous
      ENV["ADAMAS_LLVM_WORKERS"] = previous
    else
      ENV.delete("ADAMAS_LLVM_WORKERS")
    end
  end
end

def open_fd_count : Int32
  Dir.glob("/dev/fd/*").size.to_i32
rescue
  -1
end

def assert_parallel_worker_resources_reclaimed(before_tmp : ::Array(String), before_fds : Int32)
  (Dir.glob(File.join(Dir.tempdir, "adamas_llvm_par-*")) - before_tmp).should be_empty
  if before_fds >= 0
    after_fds = open_fd_count
    if after_fds >= 0
      (after_fds - before_fds).should be <= 4
    end
  end
end

describe "LLVM parallel emission rollback" do
  it "defaults to serial emission and leaves no parallel worker artifacts" do
    before_tmp = Dir.glob(File.join(Dir.tempdir, "adamas_llvm_par-*"))
    mod = Adamas::MIR::Module.new("parallel_emission_default_serial")
    function = mod.create_function("default_serial_probe", Adamas::MIR::TypeRef::INT32)
    builder = Adamas::MIR::Builder.new(function)
    builder.ret(builder.const_int(1_i64, Adamas::MIR::TypeRef::INT32))
    gen = ParallelEmissionRollbackProbeGenerator.new(mod)
    gen.emit_type_metadata = false
    gen.reachability = false
    with_worker_env(nil) do
      gen.configured_parallel_workers.should eq(1)
      Adamas::Compiler::BootstrapEnv.llvm_worker_count.should eq(1)
      gen.generate.should contain("define i32 @default_serial_probe")
    end
    (Dir.glob(File.join(Dir.tempdir, "adamas_llvm_par-*")) - before_tmp).should be_empty
  end

  it "treats invalid worker overrides as serial and bounds large overrides" do
    mod = Adamas::MIR::Module.new("parallel_emission_worker_override_bounds")
    function = mod.create_function("worker_override_probe", Adamas::MIR::TypeRef::VOID)
    Adamas::MIR::Builder.new(function).ret
    {
      {nil, 1},
      {"", 1},
      {"not-an-int", 1},
      {"0", 1},
      {"-4", 1},
      {"2", 2},
      {"999", 8},
    }.each do |value, expected|
      gen = ParallelEmissionRollbackProbeGenerator.new(mod)
      with_worker_env(value) do
        gen.configured_parallel_workers.should eq(expected)
        Adamas::Compiler::BootstrapEnv.llvm_worker_count.should eq(expected)
      end
    end
  end

  it "keeps the parent-emitted function on a successful parallel run" do
    mod = Adamas::MIR::Module.new("parallel_emission_success")
    mod.add_global("parallel_probe_global", Adamas::MIR::TypeRef::INT32)
    large = mod.create_function("Unicode.casefold_ranges", Adamas::MIR::TypeRef::INT32)
    large_builder = Adamas::MIR::Builder.new(large)
    large_builder.global_load("parallel_probe_global", Adamas::MIR::TypeRef::INT32)
    empty_args = [] of Adamas::MIR::ValueId
    large_builder.extern_call("parallel_probe_missing", empty_args, Adamas::MIR::TypeRef::INT32)
    large_builder.const_string("parallel-replay")
    last = 0_u32
    6_000.times do |idx|
      last = large_builder.const_int(idx.to_i64, Adamas::MIR::TypeRef::INT32)
    end
    large_builder.ret(last)

    worker_module_type = mod.type_registry.create_type(Adamas::MIR::TypeKind::Reference, "ParallelWorkerModule", 8_u64, 8_u32)
    worker_module_ref = Adamas::MIR::TypeRef.new(worker_module_type.id)
    mod.register_module_type(worker_module_ref)
    called_helper = mod.create_function("parallel_worker_called_helper", Adamas::MIR::TypeRef::INT32)
    called_helper_builder = Adamas::MIR::Builder.new(called_helper)
    called_helper_builder.ret(called_helper_builder.const_int(7_i64, Adamas::MIR::TypeRef::INT32))
    worker_probe = mod.create_function("parallel_worker_side_effect_probe", Adamas::MIR::TypeRef::INT32)
    worker_probe_builder = Adamas::MIR::Builder.new(worker_probe)
    worker_probe_builder.global_load("parallel_probe_global", Adamas::MIR::TypeRef::INT32)
    worker_probe_builder.const_string("parallel-worker-replay")
    worker_probe_builder.const_nil_typed(worker_module_ref)
    worker_probe_args = [] of Adamas::MIR::ValueId
    worker_probe_builder.extern_call("parallel_worker_missing", worker_probe_args, Adamas::MIR::TypeRef::INT32)
    worker_probe_builder.call(called_helper.id, worker_probe_args, Adamas::MIR::TypeRef::INT32)
    worker_probe_builder.ret(worker_probe_builder.const_int(1_i64, Adamas::MIR::TypeRef::INT32))

    40.times do |idx|
      filler = mod.create_function("filler#{idx}", Adamas::MIR::TypeRef::VOID)
      Adamas::MIR::Builder.new(filler).ret
    end

    main = mod.create_function("__adamas_main", Adamas::MIR::TypeRef::VOID)
    main_builder = Adamas::MIR::Builder.new(main)
    call_args = [] of Adamas::MIR::ValueId
    main_builder.call(large.id, call_args, Adamas::MIR::TypeRef::INT32)
    main_builder.ret

    gen = ParallelEmissionRollbackProbeGenerator.new(mod)
    gen.emit_type_metadata = false
    gen.reachability = false
    output = with_parallel_workers { gen.generate }
    output.scan("define i32 @Unicode$Dcasefold_ranges").size.should eq(1)
    output.scan("declare i32 @parallel_probe_missing(...)").size.should eq(1)
    output.scan("parallel-replay").size.should eq(1)
    output.scan("declare i32 @parallel_worker_missing(...)").size.should eq(1)
    output.scan("parallel-worker-replay").size.should eq(1)
    output.scan("define i32 @parallel_worker_called_helper").size.should eq(1)
    output.scan("@.module.singleton.#{worker_module_ref.id} = private global").size.should eq(1)
    gen.called_function?("parallel_worker_missing").should be_true
    gen.singleton_global?(worker_module_ref).should be_true
  end

  it "does not lose a parent-emitted function when a worker fails" do
    mod = Adamas::MIR::Module.new("parallel_emission_rollback")
    mod.add_global("parallel_probe_global", Adamas::MIR::TypeRef::INT32)

    large = mod.create_function("Unicode.casefold_ranges", Adamas::MIR::TypeRef::INT32)
    large_builder = Adamas::MIR::Builder.new(large)
    large_builder.global_load("parallel_probe_global", Adamas::MIR::TypeRef::INT32)
    empty_args = [] of Adamas::MIR::ValueId
    large_builder.extern_call("parallel_probe_missing", empty_args, Adamas::MIR::TypeRef::INT32)
    large_builder.const_string("parallel-replay")
    last = 0_u32
    6_000.times do |idx|
      last = large_builder.const_int(idx.to_i64, Adamas::MIR::TypeRef::INT32)
    end
    large_builder.ret(last)

    failing = mod.create_function("force_worker_failure", Adamas::MIR::TypeRef::VOID)
    Adamas::MIR::Builder.new(failing).ret

    40.times do |idx|
      filler = mod.create_function("filler#{idx}", Adamas::MIR::TypeRef::VOID)
      Adamas::MIR::Builder.new(filler).ret
    end

    main = mod.create_function("__adamas_main", Adamas::MIR::TypeRef::VOID)
    main_builder = Adamas::MIR::Builder.new(main)
    call_args = [] of Adamas::MIR::ValueId
    main_builder.call(large.id, call_args, Adamas::MIR::TypeRef::INT32)
    main_builder.ret

    gen = ParallelEmissionRollbackProbeGenerator.new(mod)
    gen.emit_type_metadata = false
    gen.reachability = false
    gen.no_prelude = true
    gen.worker_mir_opt = true
    output = with_parallel_workers { gen.generate }

    output.scan("define i32 @Unicode$Dcasefold_ranges").size.should eq(1)
    output.should_not contain("declare i32 @Unicode$Dcasefold_ranges")
    output.should_not contain("ABORT stub for unlowered method: Unicode$Dcasefold_ranges")
    output.scan("declare i32 @parallel_probe_missing(...)").size.should eq(1)
  end

  it "retries after a signaled worker and reaps all worker artifacts" do
    before_tmp = Dir.glob(File.join(Dir.tempdir, "adamas_llvm_par-*"))
    mod = Adamas::MIR::Module.new("parallel_emission_signal_retry")
    mod.add_global("parallel_probe_global", Adamas::MIR::TypeRef::INT32)

    large = mod.create_function("Unicode.casefold_ranges", Adamas::MIR::TypeRef::INT32)
    large_builder = Adamas::MIR::Builder.new(large)
    large_builder.global_load("parallel_probe_global", Adamas::MIR::TypeRef::INT32)
    empty_args = [] of Adamas::MIR::ValueId
    large_builder.extern_call("parallel_probe_missing", empty_args, Adamas::MIR::TypeRef::INT32)
    large_builder.const_string("parallel-replay")
    last = 0_u32
    6_000.times do |idx|
      last = large_builder.const_int(idx.to_i64, Adamas::MIR::TypeRef::INT32)
    end
    large_builder.ret(last)

    failing = mod.create_function("force_worker_signal_failure", Adamas::MIR::TypeRef::VOID)
    Adamas::MIR::Builder.new(failing).ret
    40.times do |idx|
      filler = mod.create_function("filler_signal#{idx}", Adamas::MIR::TypeRef::VOID)
      Adamas::MIR::Builder.new(filler).ret
    end

    main = mod.create_function("__adamas_main", Adamas::MIR::TypeRef::VOID)
    main_builder = Adamas::MIR::Builder.new(main)
    call_args = [] of Adamas::MIR::ValueId
    main_builder.call(large.id, call_args, Adamas::MIR::TypeRef::INT32)
    main_builder.ret

    gen = ParallelEmissionRollbackProbeGenerator.new(mod)
    gen.emit_type_metadata = false
    gen.reachability = false
    output = with_parallel_workers { gen.generate }

    output.scan("define i32 @Unicode$Dcasefold_ranges").size.should eq(1)
    output.should_not contain("declare i32 @Unicode$Dcasefold_ranges")
    output.should_not contain("ABORT stub for unlowered method: Unicode$Dcasefold_ranges")
    output.scan("declare i32 @parallel_probe_missing(...)").size.should eq(1)
    output.scan("parallel-replay").size.should eq(1)
    (Dir.glob(File.join(Dir.tempdir, "adamas_llvm_par-*")) - before_tmp).should be_empty
  end

  it "retries after a worker IndexError instead of swallowing it" do
    mod = Adamas::MIR::Module.new("parallel_emission_index_error_retry")
    large = mod.create_function("Unicode.casefold_ranges", Adamas::MIR::TypeRef::INT32)
    large_builder = Adamas::MIR::Builder.new(large)
    last = 0_u32
    6_000.times do |idx|
      last = large_builder.const_int(idx.to_i64, Adamas::MIR::TypeRef::INT32)
    end
    large_builder.ret(last)

    failing = mod.create_function("force_worker_index_error", Adamas::MIR::TypeRef::VOID)
    Adamas::MIR::Builder.new(failing).ret
    40.times do |idx|
      filler = mod.create_function("filler_index#{idx}", Adamas::MIR::TypeRef::VOID)
      Adamas::MIR::Builder.new(filler).ret
    end

    main = mod.create_function("__adamas_main", Adamas::MIR::TypeRef::VOID)
    main_builder = Adamas::MIR::Builder.new(main)
    call_args = [] of Adamas::MIR::ValueId
    main_builder.call(large.id, call_args, Adamas::MIR::TypeRef::INT32)
    main_builder.ret

    gen = ParallelEmissionRollbackProbeGenerator.new(mod)
    gen.emit_type_metadata = false
    gen.reachability = false
    output = with_parallel_workers { gen.generate }

    output.scan("define i32 @Unicode$Dcasefold_ranges").size.should eq(1)
    output.should_not contain("declare i32 @Unicode$Dcasefold_ranges")
  end

  it "rejects a missing worker artifact before merge and retries cleanly" do
    mod = Adamas::MIR::Module.new("parallel_emission_missing_artifact_retry")
    large = mod.create_function("Unicode.casefold_ranges", Adamas::MIR::TypeRef::INT32)
    large_builder = Adamas::MIR::Builder.new(large)
    last = 0_u32
    6_000.times do |idx|
      last = large_builder.const_int(idx.to_i64, Adamas::MIR::TypeRef::INT32)
    end
    large_builder.ret(last)

    missing = mod.create_function("force_worker_missing_artifact", Adamas::MIR::TypeRef::VOID)
    Adamas::MIR::Builder.new(missing).ret
    40.times do |idx|
      filler = mod.create_function("filler_missing#{idx}", Adamas::MIR::TypeRef::VOID)
      Adamas::MIR::Builder.new(filler).ret
    end

    main = mod.create_function("__adamas_main", Adamas::MIR::TypeRef::VOID)
    main_builder = Adamas::MIR::Builder.new(main)
    call_args = [] of Adamas::MIR::ValueId
    main_builder.call(large.id, call_args, Adamas::MIR::TypeRef::INT32)
    main_builder.ret

    gen = ParallelEmissionRollbackProbeGenerator.new(mod)
    gen.emit_type_metadata = false
    gen.reachability = false
    output = with_parallel_workers { gen.generate }

    output.scan("define i32 @Unicode$Dcasefold_ranges").size.should eq(1)
    output.should_not contain("declare i32 @Unicode$Dcasefold_ranges")
  end

  it "does not block on a hung worker ahead of a failing worker" do
    before_tmp = Dir.glob(File.join(Dir.tempdir, "adamas_llvm_par-*"))
    before_fds = open_fd_count
    mod = Adamas::MIR::Module.new("parallel_emission_hang_timeout")
    large = mod.create_function("Unicode.casefold_ranges", Adamas::MIR::TypeRef::INT32)
    large_builder = Adamas::MIR::Builder.new(large)
    last = 0_u32
    6_000.times do |idx|
      last = large_builder.const_int(idx.to_i64, Adamas::MIR::TypeRef::INT32)
    end
    large_builder.ret(last)

    hanging = mod.create_function("force_worker_hang", Adamas::MIR::TypeRef::VOID)
    Adamas::MIR::Builder.new(hanging).ret
    failing = mod.create_function("force_worker_failure", Adamas::MIR::TypeRef::VOID)
    Adamas::MIR::Builder.new(failing).ret
    40.times do |idx|
      filler = mod.create_function("filler_hang#{idx}", Adamas::MIR::TypeRef::VOID)
      Adamas::MIR::Builder.new(filler).ret
    end

    main = mod.create_function("__adamas_main", Adamas::MIR::TypeRef::VOID)
    main_builder = Adamas::MIR::Builder.new(main)
    call_args = [] of Adamas::MIR::ValueId
    main_builder.call(large.id, call_args, Adamas::MIR::TypeRef::INT32)
    main_builder.ret

    gen = ParallelEmissionRollbackProbeGenerator.new(mod)
    gen.emit_type_metadata = false
    gen.reachability = false
    gen.parallel_worker_timeout_ms = 100
    output = with_parallel_workers { gen.generate }

    output.scan("define i32 @Unicode$Dcasefold_ranges").size.should eq(1)
    output.should_not contain("declare i32 @Unicode$Dcasefold_ranges")
    assert_parallel_worker_resources_reclaimed(before_tmp, before_fds)
  end

  it "bounds an all-hung worker set with the configured deadline" do
    before_tmp = Dir.glob(File.join(Dir.tempdir, "adamas_llvm_par-*"))
    before_fds = open_fd_count
    mod = Adamas::MIR::Module.new("parallel_emission_all_hung_timeout")
    large = mod.create_function("Unicode.casefold_ranges", Adamas::MIR::TypeRef::INT32)
    large_builder = Adamas::MIR::Builder.new(large)
    last = 0_u32
    6_000.times do |idx|
      last = large_builder.const_int(idx.to_i64, Adamas::MIR::TypeRef::INT32)
    end
    large_builder.ret(last)

    hanging = mod.create_function("force_worker_hang", Adamas::MIR::TypeRef::VOID)
    Adamas::MIR::Builder.new(hanging).ret
    40.times do |idx|
      filler = mod.create_function("filler_all_hung#{idx}", Adamas::MIR::TypeRef::VOID)
      Adamas::MIR::Builder.new(filler).ret
    end

    main = mod.create_function("__adamas_main", Adamas::MIR::TypeRef::VOID)
    main_builder = Adamas::MIR::Builder.new(main)
    call_args = [] of Adamas::MIR::ValueId
    main_builder.call(large.id, call_args, Adamas::MIR::TypeRef::INT32)
    main_builder.ret

    gen = ParallelEmissionRollbackProbeGenerator.new(mod)
    gen.emit_type_metadata = false
    gen.reachability = false
    gen.parallel_worker_timeout_ms = 100
    output = with_parallel_workers { gen.generate }

    output.scan("define i32 @Unicode$Dcasefold_ranges").size.should eq(1)
    output.should_not contain("declare i32 @Unicode$Dcasefold_ranges")
    assert_parallel_worker_resources_reclaimed(before_tmp, before_fds)
  end

  it "keeps external IO on the serial path" do
    mod = Adamas::MIR::Module.new("parallel_emission_external_io")
    large = mod.create_function("Unicode.casefold_ranges", Adamas::MIR::TypeRef::INT32)
    large_builder = Adamas::MIR::Builder.new(large)
    last = 0_u32
    6_000.times do |idx|
      last = large_builder.const_int(idx.to_i64, Adamas::MIR::TypeRef::INT32)
    end
    large_builder.ret(last)
    40.times do |idx|
      filler = mod.create_function("filler_external#{idx}", Adamas::MIR::TypeRef::VOID)
      Adamas::MIR::Builder.new(filler).ret
    end

    gen = ParallelEmissionRollbackProbeGenerator.new(mod)
    gen.emit_type_metadata = false
    gen.reachability = false
    sink = IO::Memory.new
    with_parallel_workers { gen.generate(sink) }.should eq("")
    sink.to_s.scan("define i32 @Unicode$Dcasefold_ranges").size.should eq(1)
  end

  it "does not retry a parent emission exception" do
    mod = Adamas::MIR::Module.new("parallel_emission_parent_failure")
    large = mod.create_function("force_parent_failure", Adamas::MIR::TypeRef::INT32)
    large_builder = Adamas::MIR::Builder.new(large)
    last = 0_u32
    6_000.times do |idx|
      last = large_builder.const_int(idx.to_i64, Adamas::MIR::TypeRef::INT32)
    end
    large_builder.ret(last)
    40.times do |idx|
      filler = mod.create_function("filler_parent#{idx}", Adamas::MIR::TypeRef::VOID)
      Adamas::MIR::Builder.new(filler).ret
    end

    gen = ParallelEmissionRollbackProbeGenerator.new(mod)
    gen.emit_type_metadata = false
    gen.reachability = false
    ParallelEmissionRollbackProbeGenerator.reset_parent_failure_trigger
    expect_raises(Exception, /forced parent emission failure/) do
      with_parallel_workers { gen.generate }
    end
  end
end
