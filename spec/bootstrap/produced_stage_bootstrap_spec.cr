require "spec"
require "file_utils"

module ProducedStageBootstrapSpec
  ROOT                              = File.expand_path("../..", __DIR__)
  COMPILER                          = File.expand_path(ENV["ADAMAS_SPEC_COMPILER"]? || raise("ADAMAS_SPEC_COMPILER must point to a fresh compiler build"))
  RUN_SAFE                          = File.join(ROOT, "scripts", "run_safe.sh")
  SOURCE                            = File.join(ROOT, "src", "adamas.cr")
  TERMIOS                           = File.join(ROOT, "src", "stdlib", "termios.cr")
  FIXTURE                           = File.join(__DIR__, "test_data", "full_prelude_stdout_smoke.cr")
  POINTER_IVAR_FIXTURE              = File.join(__DIR__, "test_data", "generic_pointer_ivar_index.cr")
  POINTER_IVAR_RUNTIME_FIXTURE      = File.join(__DIR__, "test_data", "generic_pointer_ivar_runtime.cr")
  RETURNED_STRUCT_FIXTURE           = File.join(__DIR__, "test_data", "returned_struct_escape_runtime.cr")
  TYPEREF_SET_FIXTURE               = File.join(__DIR__, "test_data", "array_typeref_set_identity_runtime.cr")
  ARRAY_TUPLE_POP_FIXTURE           = File.join(__DIR__, "test_data", "array_tuple_pop_runtime.cr")
  NILABLE_VALUE_HASH_RESIZE_FIXTURE = File.join(__DIR__, "test_data", "nilable_value_hash_resize_runtime.cr")
  NESTED_QUOTED_FLAG_FIXTURE        = File.join(__DIR__, "test_data", "nested_quoted_flag_require.cr")
  MACRO_IF_METHOD_FIXTURE           = File.join(__DIR__, "test_data", "module_macro_if_method_hir.cr")
  REPEATED_CLASS_METHOD_FIXTURE     = File.join(__DIR__, "test_data", "repeated_class_method_call.cr")
  NONVOID_SEQUENCE_FIXTURE          = File.join(__DIR__, "test_data", "nonvoid_helper_sequence_hir.cr")
  FULL_PRELUDE_MINIMAL_FIXTURE      = File.join(__DIR__, "test_data", "full_prelude_minimal_hir.cr")
  REFERENCE_ARRAY_FIND_NEXT_FIXTURE = File.join(ROOT, "spec", "hir", "test_data", "reference_array_find_next_hir.cr")
  MARKER                            = "ADAMAS_PRODUCED_STAGE_OK"
  POINTER_IVAR_MARKER               = "ADAMAS_GENERIC_POINTER_IVAR_OK"
  RETURNED_STRUCT_MARKER            = "ADAMAS_RETURNED_STRUCT_ESCAPE_OK:73,11"
  TYPEREF_SET_MARKER                = "ADAMAS_ARRAY_TYPEREF_SET_OK:uint=0,16,17;small=0,15,16;large=0,16,17"
  ARRAY_TUPLE_POP_MARKER            = "ADAMAS_ARRAY_TUPLE_POP_OK:non_nil=1;empty=1"
  NILABLE_VALUE_HASH_RESIZE_MARKER  = "ADAMAS_NILABLE_HASH_RESIZE_OK"
  NESTED_QUOTED_FLAG_MARKER         = "ADAMAS_NESTED_QUOTED_FLAG_VALUE:1"
  REFERENCE_ARRAY_FIND_NEXT_MARKER  = "generated-reference-array-find-next-ok"

  record SafeResult, status : Process::Status, output : String

  private def self.read_log(path : String) : String
    File.exists?(path) ? File.read(path) : "<missing log>"
  end

  private def self.run_safely(
    binary : String,
    timeout : Int32,
    max_mem_mb : Int32,
    args : Array(String),
    log_dir : String,
    phase : String,
  ) : SafeResult
    stdout_path = File.join(log_dir, "#{phase}.stdout.log")
    stderr_path = File.join(log_dir, "#{phase}.stderr.log")

    begin
      status = File.open(stdout_path, "w") do |stdout|
        File.open(stderr_path, "w") do |stderr|
          Process.run(
            RUN_SAFE,
            [binary, timeout.to_s, max_mem_mb.to_s] + args,
            output: stdout,
            error: stderr
          )
        end
      end

      output = String.build do |io|
        io << "=== #{phase} STDOUT ===\n" << read_log(stdout_path)
        io << "=== #{phase} STDERR ===\n" << read_log(stderr_path)
      end
      SafeResult.new(status, output)
    rescue ex
      output = String.build do |io|
        io << "run_safe invocation failed: " << ex.message << '\n'
        io << "=== #{phase} STDOUT ===\n" << read_log(stdout_path)
        io << "=== #{phase} STDERR ===\n" << read_log(stderr_path)
      end
      raise output
    end
  end

  private def self.require_executable!(result : SafeResult, artifact : String, phase : String) : Nil
    executable = File.file?(artifact) && File::Info.executable?(artifact) && File.size(artifact) > 0
    return if result.status.success? && executable

    raise String.build { |io|
      io << phase << " failed: status=" << result.status
      io << " artifact=" << artifact << " executable=" << executable << '\n'
      io << result.output
    }
  end

  private def self.require_marker!(result : SafeResult, marker : String, phase : String) : Nil
    marker_count = result.output.lines.count { |line| line.strip == marker }
    return if result.status.success? && marker_count == 1

    raise String.build { |io|
      io << phase << " failed: status=" << result.status
      io << " marker_count=" << marker_count << '\n'
      io << result.output
    }
  end

  private def self.require_main_hir!(result : SafeResult, hir_path : String) : Nil
    emitted = File.file?(hir_path) && File.size(hir_path) > 0
    has_main = emitted && File.read(hir_path).includes?("func @__adamas_main")
    return if result.status.success? && has_main

    raise String.build { |io|
      io << "produced stage2 Termios HIR emission failed: status=" << result.status
      io << " artifact=" << hir_path << " emitted=" << emitted
      io << " has_main=" << has_main << '\n'
      io << result.output
    }
  end

  private def self.require_generic_pointer_ivar_hir!(result : SafeResult, hir_path : String) : Nil
    emitted = File.file?(hir_path) && File.size(hir_path) > 0
    text = emitted ? File.read(hir_path) : ""
    has_get_entry = text.includes?("get_entry")
    has_specialized_get_entry = text.includes?("func @Hash(String, Nil)#get_entry$Int32")
    has_pointer_descriptor = text.includes?("Pointer(Hash::Entry(String, Nil))")
    has_pointer_load = text.includes?("ptr_load")
    has_index_call = text.lines.any? do |line|
      line.includes?("= call ") && line.includes?("[]$Int32(")
    end
    has_pointer_index_call = text.lines.any? do |line|
      line.includes?("= call Pointer$H$IDX$$Int32(") || line.includes?("= call Pointer#[]$Int32(")
    end
    return if result.status.success? && emitted && has_get_entry && has_specialized_get_entry &&
              has_pointer_descriptor && has_pointer_load && !has_index_call && !has_pointer_index_call

    raise String.build { |io|
      io << "produced stage2 generic pointer-ivar shape contract failed: status=" << result.status
      io << " artifact=" << hir_path << " emitted=" << emitted
      io << " has_get_entry=" << has_get_entry
      io << " has_specialized_get_entry=" << has_specialized_get_entry
      io << " has_pointer_descriptor=" << has_pointer_descriptor
      io << " has_pointer_load=" << has_pointer_load
      io << " has_index_call=" << has_index_call
      io << " has_pointer_index_call=" << has_pointer_index_call << '\n'
      io << result.output
    }
  end

  private def self.require_repeated_class_method_hir!(result : SafeResult, hir_path : String) : Nil
    emitted = File.file?(hir_path) && File.size(hir_path) > 0
    text = emitted ? File.read(hir_path) : ""
    call_count = text.lines.count do |line|
      line.includes?("= call RepeatedClassMethod.record$String(")
    end
    has_body = text.includes?("func @RepeatedClassMethod.record$String(")
    return if result.status.success? && emitted && call_count == 2 && has_body

    raise String.build { |io|
      io << "produced stage2 repeated class-method HIR contract failed: status=" << result.status
      io << " artifact=" << hir_path << " emitted=" << emitted
      io << " call_count=" << call_count << " has_body=" << has_body << '\n'
      io << result.output
    }
  end

  private def self.require_nonvoid_sequence_hir!(result : SafeResult, hir_path : String) : Nil
    emitted = File.file?(hir_path) && File.size(hir_path) > 0
    text = emitted ? File.read(hir_path) : ""
    function_start = text.index("func @GenericIfCallSequence(Int32)#upsert$Int32_Int32")
    function_end = function_start ? text.index("\nfunc @", function_start + 1) : nil
    function_text = if function_start
                      text.byte_slice(function_start, (function_end || text.bytesize) - function_start)
                    else
                      ""
                    end
    has_helper_call = function_text.includes?("#malloc_entries$Int32")
    has_tail_binding = function_text.includes?("local \"hash\"")
    return_line = function_text.lines.reverse.find { |line| line.strip.starts_with?("return %") }
    return_id = return_line.try do |line|
      match = line.match(/return %(\d+)/)
      match ? match[1] : nil
    end
    return_definition = return_id.try do |id|
      function_text.lines.find { |line| line.strip.starts_with?("%#{id} =") }
    end
    has_non_nil_return = !!return_definition && !return_definition.not_nil!.includes?("literal nil : Nil")
    return if result.status.success? && emitted && has_helper_call && has_tail_binding && has_non_nil_return

    raise String.build { |io|
      io << "produced stage2 non-void helper sequence HIR contract failed: status=" << result.status
      io << " artifact=" << hir_path << " emitted=" << emitted
      io << " has_helper_call=" << has_helper_call
      io << " has_tail_binding=" << has_tail_binding
      io << " has_non_nil_return=" << has_non_nil_return << '\n'
      io << result.output
    }
  end

  private def self.require_full_prelude_minimal_hir!(result : SafeResult, hir_path : String) : Nil
    emitted = File.file?(hir_path) && File.size(hir_path) > 0
    has_main = emitted && File.read(hir_path).includes?("func @__adamas_main")
    return if result.status.success? && emitted && has_main

    raise String.build { |io|
      io << "produced stage2 minimal full-prelude HIR contract failed: status=" << result.status
      io << " artifact=" << hir_path << " emitted=" << emitted
      io << " has_main=" << has_main << '\n'
      io << result.output
    }
  end

  private def self.require_macro_if_method_hir!(result : SafeResult, hir_path : String) : Nil
    emitted = File.file?(hir_path) && File.size(hir_path) > 0
    text = emitted ? File.read(hir_path) : ""
    has_function = text.includes?("func @M.foo() -> 4")
    has_typed_call = text.lines.any? { |line| line.includes?("call M.foo() : 4") }
    has_literal = text.includes?("literal 2")
    has_unresolved_call = text.lines.any? { |line| line.includes?("call M.foo() : 0") }
    function_start = text.index("func @M.foo()")
    function_end = function_start ? text.index("\nfunc @", function_start + 1) : nil
    function_text = if function_start
                      text.byte_slice(function_start, (function_end || text.bytesize) - function_start)
                    else
                      ""
                    end
    has_nil_return = function_text.includes?("literal nil : Nil") || function_text.lines.any? { |line| line.strip == "return" }
    return if result.status.success? && emitted && has_function && has_typed_call && has_literal && !has_unresolved_call && !has_nil_return

    raise String.build { |io|
      io << "produced stage2 macro-if module method HIR contract failed: status=" << result.status
      io << " artifact=" << hir_path << " emitted=" << emitted
      io << " has_function=" << has_function
      io << " has_typed_call=" << has_typed_call
      io << " has_literal=" << has_literal
      io << " has_unresolved_call=" << has_unresolved_call
      io << " has_nil_return=" << has_nil_return << '\n'
      io << result.output
    }
  end

  def self.verify : Nil
    workdir = File.join(Dir.tempdir, "adamas_produced_stage_#{Process.pid}_#{Random.rand(1_000_000)}")
    Dir.mkdir(workdir)
    provided_stage2 = ENV["ADAMAS_PRODUCED_STAGE2"]?
    stage2 = provided_stage2 ? File.expand_path(provided_stage2) : File.join(workdir, "adamas-stage2")
    termios_stem = File.join(workdir, "termios")
    termios_hir = "#{termios_stem}.hir"
    pointer_ivar_stem = File.join(workdir, "generic-pointer-ivar")
    pointer_ivar_hir = "#{pointer_ivar_stem}.hir"
    pointer_ivar_binary = File.join(workdir, "generic-pointer-ivar-run")
    returned_struct_binary = File.join(workdir, "returned-struct-run")
    typeref_set_binary = File.join(workdir, "typeref-set-run")
    array_tuple_pop_binary = File.join(workdir, "array-tuple-pop-run")
    nilable_value_hash_resize_binary = File.join(workdir, "nilable-value-hash-resize-run")
    nested_quoted_flag_binary = File.join(workdir, "nested-quoted-flag-run")
    repeated_class_method_stem = File.join(workdir, "repeated-class-method")
    repeated_class_method_hir = "#{repeated_class_method_stem}.hir"
    nonvoid_sequence_stem = File.join(workdir, "nonvoid-helper-sequence")
    nonvoid_sequence_hir = "#{nonvoid_sequence_stem}.hir"
    full_prelude_minimal_stem = File.join(workdir, "full-prelude-minimal")
    full_prelude_minimal_hir = "#{full_prelude_minimal_stem}.hir"
    macro_if_method_stem = File.join(workdir, "module-macro-if-method")
    macro_if_method_hir = "#{macro_if_method_stem}.hir"
    reference_array_find_next_binary = File.join(workdir, "reference-array-find-next-run")
    smoke = File.join(workdir, "full-prelude-smoke")

    begin
      if provided_stage2
        executable = File.file?(stage2) && File::Info.executable?(stage2) && File.size(stage2) > 0
        raise "provided ADAMAS_PRODUCED_STAGE2 is not executable: #{stage2}" unless executable
      else
        stage2_result = run_safely(
          COMPILER,
          600,
          8192,
          [SOURCE, "-o", stage2],
          workdir,
          "stage2-build"
        )
        require_executable!(stage2_result, stage2, "produced stage2 build")
      end

      macro_if_method_result = run_safely(
        stage2,
        30,
        1024,
        [MACRO_IF_METHOD_FIXTURE, "--no-prelude", "--emit", "hir", "--no-link", "-o", macro_if_method_stem],
        workdir,
        "module-macro-if-method-hir"
      )
      require_macro_if_method_hir!(macro_if_method_result, macro_if_method_hir)

      repeated_class_method_result = run_safely(
        stage2,
        60,
        2048,
        [REPEATED_CLASS_METHOD_FIXTURE, "--no-prelude", "--emit", "hir", "--no-link", "-o", repeated_class_method_stem],
        workdir,
        "repeated-class-method-hir"
      )
      require_repeated_class_method_hir!(repeated_class_method_result, repeated_class_method_hir)

      nonvoid_sequence_result = run_safely(
        stage2,
        60,
        2048,
        [NONVOID_SEQUENCE_FIXTURE, "--no-prelude", "--emit", "hir", "--no-link", "-o", nonvoid_sequence_stem],
        workdir,
        "nonvoid-helper-sequence-hir"
      )
      require_nonvoid_sequence_hir!(nonvoid_sequence_result, nonvoid_sequence_hir)

      full_prelude_minimal_result = run_safely(
        stage2,
        60,
        2048,
        [FULL_PRELUDE_MINIMAL_FIXTURE, "--emit", "hir", "--no-link", "-o", full_prelude_minimal_stem],
        workdir,
        "full-prelude-minimal-hir"
      )
      require_full_prelude_minimal_hir!(full_prelude_minimal_result, full_prelude_minimal_hir)

      reference_array_find_next_build_result = run_safely(
        stage2,
        120,
        4096,
        [REFERENCE_ARRAY_FIND_NEXT_FIXTURE, "-o", reference_array_find_next_binary],
        workdir,
        "reference-array-find-next-build"
      )
      require_executable!(
        reference_array_find_next_build_result,
        reference_array_find_next_binary,
        "produced stage2 reference Array#find runtime build"
      )

      reference_array_find_next_run_result = run_safely(
        reference_array_find_next_binary,
        10,
        512,
        [] of String,
        workdir,
        "reference-array-find-next-run"
      )
      require_marker!(
        reference_array_find_next_run_result,
        REFERENCE_ARRAY_FIND_NEXT_MARKER,
        "produced reference Array#find execution"
      )

      pointer_ivar_result = run_safely(
        stage2,
        60,
        2048,
        [POINTER_IVAR_FIXTURE, "--no-prelude", "--emit", "hir", "--no-link", "-o", pointer_ivar_stem],
        workdir,
        "generic-pointer-ivar-hir"
      )
      require_generic_pointer_ivar_hir!(pointer_ivar_result, pointer_ivar_hir)

      pointer_ivar_build_result = run_safely(
        stage2,
        60,
        2048,
        [POINTER_IVAR_RUNTIME_FIXTURE, "--no-prelude", "-o", pointer_ivar_binary],
        workdir,
        "generic-pointer-ivar-build"
      )
      require_executable!(pointer_ivar_build_result, pointer_ivar_binary, "produced stage2 generic pointer-ivar runtime build")

      pointer_ivar_run_result = run_safely(
        pointer_ivar_binary,
        10,
        512,
        [] of String,
        workdir,
        "generic-pointer-ivar-run"
      )
      require_marker!(pointer_ivar_run_result, POINTER_IVAR_MARKER, "produced generic pointer-ivar execution")

      returned_struct_build_result = run_safely(
        stage2,
        60,
        2048,
        [RETURNED_STRUCT_FIXTURE, "--no-prelude", "-o", returned_struct_binary],
        workdir,
        "returned-struct-build"
      )
      require_executable!(returned_struct_build_result, returned_struct_binary, "produced stage2 returned-struct build")

      returned_struct_run_result = run_safely(
        returned_struct_binary,
        10,
        512,
        [] of String,
        workdir,
        "returned-struct-run"
      )
      require_marker!(returned_struct_run_result, RETURNED_STRUCT_MARKER, "produced returned-struct escape execution")

      typeref_set_build_result = run_safely(
        stage2,
        120,
        4096,
        [TYPEREF_SET_FIXTURE, "-o", typeref_set_binary],
        workdir,
        "typeref-set-build"
      )
      require_executable!(typeref_set_build_result, typeref_set_binary, "produced stage2 TypeRef Set identity build")

      typeref_set_run_result = run_safely(
        typeref_set_binary,
        10,
        512,
        [] of String,
        workdir,
        "typeref-set-run"
      )
      require_marker!(typeref_set_run_result, TYPEREF_SET_MARKER, "produced TypeRef Set identity execution")

      array_tuple_pop_build_result = run_safely(
        stage2,
        60,
        2048,
        [ARRAY_TUPLE_POP_FIXTURE, "--no-prelude", "-o", array_tuple_pop_binary],
        workdir,
        "array-tuple-pop-build"
      )
      require_executable!(array_tuple_pop_build_result, array_tuple_pop_binary, "produced stage2 Array tuple pop build")

      array_tuple_pop_run_result = run_safely(
        array_tuple_pop_binary,
        10,
        512,
        [] of String,
        workdir,
        "array-tuple-pop-run"
      )
      require_marker!(array_tuple_pop_run_result, ARRAY_TUPLE_POP_MARKER, "produced Array tuple pop execution")

      nilable_value_hash_resize_build_result = run_safely(
        stage2,
        120,
        4096,
        [NILABLE_VALUE_HASH_RESIZE_FIXTURE, "-o", nilable_value_hash_resize_binary],
        workdir,
        "nilable-value-hash-resize-build"
      )
      require_executable!(nilable_value_hash_resize_build_result, nilable_value_hash_resize_binary, "produced stage2 nilable-value Hash resize build")

      nilable_value_hash_resize_run_result = run_safely(
        nilable_value_hash_resize_binary,
        10,
        512,
        [] of String,
        workdir,
        "nilable-value-hash-resize-run"
      )
      require_marker!(nilable_value_hash_resize_run_result, NILABLE_VALUE_HASH_RESIZE_MARKER, "produced nilable-value Hash resize execution")

      nested_quoted_flag_build_result = run_safely(
        stage2,
        60,
        2048,
        [NESTED_QUOTED_FLAG_FIXTURE, "--no-prelude", "-o", nested_quoted_flag_binary],
        workdir,
        "nested-quoted-flag-build"
      )
      require_executable!(nested_quoted_flag_build_result, nested_quoted_flag_binary, "produced stage2 nested quoted-flag build")

      nested_quoted_flag_run_result = run_safely(
        nested_quoted_flag_binary,
        10,
        512,
        [] of String,
        workdir,
        "nested-quoted-flag-run"
      )
      require_marker!(nested_quoted_flag_run_result, NESTED_QUOTED_FLAG_MARKER, "produced nested quoted-flag require execution")

      termios_result = run_safely(
        stage2,
        60,
        2048,
        [TERMIOS, "--no-prelude", "--emit", "hir", "--no-link", "-o", termios_stem],
        workdir,
        "termios-hir"
      )
      require_main_hir!(termios_result, termios_hir)

      smoke_result = run_safely(
        stage2,
        120,
        4096,
        [FIXTURE, "-o", smoke],
        workdir,
        "smoke-build"
      )
      require_executable!(smoke_result, smoke, "produced stage2 full-prelude smoke build")

      run_result = run_safely(
        smoke,
        20,
        2048,
        [] of String,
        workdir,
        "smoke-run"
      )
      require_marker!(run_result, MARKER, "produced full-prelude smoke execution")
    ensure
      # The compiler keeps intermediates beside -o. Removing the private
      # directory covers binaries, .ll/.opt.ll, .o, .dwarf, and phase logs.
      FileUtils.rm_rf(workdir) if Dir.exists?(workdir)
    end
  end
end

describe "produced-stage bootstrap" do
  it "builds and executes an exact-marker full-prelude smoke with a fresh stage2" do
    ProducedStageBootstrapSpec.verify
  end
end
