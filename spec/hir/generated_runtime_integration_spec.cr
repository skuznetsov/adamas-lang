require "../spec_helper"

module GeneratedHIRRuntimeSpec
  ROOT           = File.expand_path("../..", __DIR__)
  COMPILER       = ENV["ADAMAS_SPEC_COMPILER"]? || raise("ADAMAS_SPEC_COMPILER must point to a fresh compiler build")
  RUN_SAFE       = File.join(ROOT, "scripts", "run_safe.sh")
  FIXTURE        = File.join(__DIR__, "test_data", "module_remove_function_readd.cr")
  VALUE_HASH_FIXTURE = File.join(__DIR__, "test_data", "value_hash_call_identity.cr")
  METHOD_EFFECT_FIXTURE = File.join(__DIR__, "test_data", "method_effect_provider_runtime.cr")
  STDLIB_FIXTURE = File.join(__DIR__, "test_data", "stdlib_specialization_contract.cr")
  NILABLE_LOOP_ENSURE_FIXTURE = File.join(__DIR__, "test_data", "nilable_loop_ensure_runtime.cr")
  REFERENCE_ARRAY_FIND_NEXT_FIXTURE = File.join(__DIR__, "test_data", "reference_array_find_next_hir.cr")
  DEQUE_INCLUDES_FIXTURE = File.join(__DIR__, "test_data", "deque_includes_runtime.cr")

  private def self.run_safely(binary : String, timeout : Int32, max_mem_mb : Int32, args : Array(String)) : {Process::Status, String}
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run(
      RUN_SAFE,
      [binary, timeout.to_s, max_mem_mb.to_s] + args,
      output: stdout,
      error: stderr
    )
    {status, "#{stdout}#{stderr}"}
  end

  def self.compile_and_run_registry_fixture : String
    stem = File.join(Dir.tempdir, "adamas_generated_hir_registry_#{Process.pid}_#{Random.rand(1_000_000)}")
    artifacts = [stem, "#{stem}.ll", "#{stem}.ll.opt.ll", "#{stem}.o", "#{stem}.dwarf"]

    begin
      compile_status, compile_output = run_safely(
        COMPILER,
        360,
        8192,
        [FIXTURE, "-o", stem]
      )
      raise "generated fixture compilation failed:\n#{compile_output}" unless compile_status.success?

      run_status, run_output = run_safely(stem, 20, 2048, [] of String)
      raise "generated fixture execution failed:\n#{run_output}" unless run_status.success?
      run_output
    ensure
      artifacts.each { |path| File.delete(path) if File.exists?(path) }
    end
  end

  def self.compile_and_run_value_hash_fixture : String
    stem = File.join(Dir.tempdir, "adamas_generated_hir_value_hash_#{Process.pid}_#{Random.rand(1_000_000)}")
    artifacts = [stem, "#{stem}.ll", "#{stem}.ll.opt.ll", "#{stem}.o", "#{stem}.dwarf"]

    begin
      compile_status, compile_output = run_safely(
        COMPILER,
        360,
        8192,
        [VALUE_HASH_FIXTURE, "-o", stem]
      )
      raise "generated value hash fixture compilation failed:\n#{compile_output}" unless compile_status.success?

      run_status, run_output = run_safely(stem, 20, 2048, [] of String)
      raise "generated value hash fixture execution failed:\n#{run_output}" unless run_status.success?
      run_output
    ensure
      artifacts.each { |path| File.delete(path) if File.exists?(path) }
    end
  end

  def self.compile_and_run_method_effect_fixture : String
    stem = File.join(Dir.tempdir, "adamas_generated_method_effect_#{Process.pid}_#{Random.rand(1_000_000)}")
    artifacts = [stem, "#{stem}.ll", "#{stem}.ll.opt.ll", "#{stem}.o", "#{stem}.dwarf"]

    begin
      compile_status, compile_output = run_safely(
        COMPILER,
        360,
        8192,
        [METHOD_EFFECT_FIXTURE, "-o", stem]
      )
      raise "generated method-effect fixture compilation failed:\n#{compile_output}" unless compile_status.success?

      run_status, run_output = run_safely(stem, 20, 2048, [] of String)
      raise "generated method-effect fixture execution failed:\n#{run_output}" unless run_status.success?
      run_output
    ensure
      artifacts.each { |path| File.delete(path) if File.exists?(path) }
    end
  end

  def self.emit_stdlib_specialization_hir : String
    stem = File.join(Dir.tempdir, "adamas_stdlib_specialization_#{Process.pid}_#{Random.rand(1_000_000)}")
    hir_path = "#{stem}.hir"
    artifacts = [stem, hir_path, "#{stem}.ll", "#{stem}.ll.opt.ll", "#{stem}.o", "#{stem}.dwarf"]

    begin
      status, output = run_safely(
        COMPILER,
        360,
        8192,
        [STDLIB_FIXTURE, "--emit", "hir", "--no-link", "-o", stem]
      )
      raise "stdlib specialization HIR emission failed:\n#{output}" unless status.success?
      raise "stdlib specialization HIR was not emitted" unless File.exists?(hir_path)
      File.read(hir_path)
    ensure
      artifacts.each { |path| File.delete(path) if File.exists?(path) }
    end
  end


  def self.compile_and_run_nilable_loop_ensure_fixture : String
    stem = File.join(Dir.tempdir, "adamas_nilable_loop_ensure_#{Process.pid}_#{Random.rand(1_000_000)}")
    artifacts = [stem, "#{stem}.ll", "#{stem}.ll.opt.ll", "#{stem}.o", "#{stem}.dwarf"]

    begin
      compile_status, compile_output = run_safely(
        COMPILER,
        360,
        8192,
        [NILABLE_LOOP_ENSURE_FIXTURE, "-o", stem]
      )
      raise "nilable loop/ensure fixture compilation failed:\n#{compile_output}" unless compile_status.success?

      run_status, run_output = run_safely(stem, 20, 2048, [] of String)
      raise "nilable loop/ensure fixture execution failed:\n#{run_output}" unless run_status.success?
      run_output
    ensure
      artifacts.each { |path| File.delete(path) if File.exists?(path) }
    end
  end

  def self.compile_and_run_reference_array_find_next_fixture : String
    stem = File.join(Dir.tempdir, "adamas_reference_array_find_next_#{Process.pid}_#{Random.rand(1_000_000)}")
    artifacts = [stem, "#{stem}.ll", "#{stem}.ll.opt.ll", "#{stem}.o", "#{stem}.dwarf"]

    begin
      compile_status, compile_output = run_safely(
        COMPILER,
        360,
        8192,
        [REFERENCE_ARRAY_FIND_NEXT_FIXTURE, "-o", stem]
      )
      raise "reference Array#find fixture compilation failed:\n#{compile_output}" unless compile_status.success?

      run_status, run_output = run_safely(stem, 20, 2048, [] of String)
      raise "reference Array#find fixture execution failed:\n#{run_output}" unless run_status.success?
      run_output
    ensure
      artifacts.each { |path| File.delete(path) if File.exists?(path) }
    end
  end

  def self.compile_and_run_deque_includes_fixture : String
    stem = File.join(Dir.tempdir, "adamas_deque_includes_#{Process.pid}_#{Random.rand(1_000_000)}")
    artifacts = [stem, "#{stem}.ll", "#{stem}.ll.opt.ll", "#{stem}.o", "#{stem}.dwarf"]

    begin
      compile_status, compile_output = run_safely(
        COMPILER,
        360,
        8192,
        [DEQUE_INCLUDES_FIXTURE, "-o", stem]
      )
      raise "Deque#includes? fixture compilation failed:\n#{compile_output}" unless compile_status.success?

      run_status, run_output = run_safely(stem, 20, 2048, [] of String)
      raise "Deque#includes? fixture execution failed:\n#{run_output}" unless run_status.success?
      run_output
    ensure
      artifacts.each { |path| File.delete(path) if File.exists?(path) }
    end
  end
end

describe "generated HIR runtime" do
  it "removes and re-adds HIR functions without splitting registry indexes" do
    output = GeneratedHIRRuntimeSpec.compile_and_run_registry_fixture
    output.should contain("generated-hir-function-registry-ok")
  end

  it "preserves Call identity and fields through a HIR Value hash" do
    output = GeneratedHIRRuntimeSpec.compile_and_run_value_hash_fixture
    output.should contain("generated-hir-value-hash-call-identity-ok")
  end

  it "dispatches method effects through the concrete HIR module" do
    output = GeneratedHIRRuntimeSpec.compile_and_run_method_effect_fixture
    output.should contain("generated-method-effect-provider-ok")
  end

  it "preserves real stdlib formatter and nested-struct specialization shapes" do
    hir = GeneratedHIRRuntimeSpec.emit_stdlib_specialization_hir

    hir.should contain("func @String::Formatter(Tuple(Float64))#arg_at$Nil")
    hir.should contain("func @String::Formatter(Tuple(Float64))#float$String::Formatter::Flags_Float64")
    hir.should_not contain("String::Formatter(Tuple(Float64))#float$String::Formatter::Flags_Int32")
    hir.should match(/call %\d+\.Outer::Inner::Point#inspect\(\)/)
    hir.should contain("func @Outer::Inner::Point#inspect$String::Builder")
  end

  it "preserves nilable outer-local assignments through looped ensure scopes" do
    output = GeneratedHIRRuntimeSpec.compile_and_run_nilable_loop_ensure_fixture
    output.should contain("generated-nilable-loop-ensure-ok")
  end

  it "returns a reference element from Array#find when the predicate uses next" do
    output = GeneratedHIRRuntimeSpec.compile_and_run_reference_array_find_next_fixture
    output.should contain("generated-reference-array-find-next-ok")
    output.should_not contain("generated-reference-array-find-next-wrong")
  end

  it "preserves nested yield callbacks through Deque#includes?" do
    output = GeneratedHIRRuntimeSpec.compile_and_run_deque_includes_fixture
    output.should contain("generated-deque-includes-ok")
    output.should_not contain("generated-deque-includes-wrong")
  end
end
