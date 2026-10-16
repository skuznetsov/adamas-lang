require "./semantic_cli_helpers"

include SemanticCliSpecHelpers

module Adamas::Compiler
  class CLI
    def compile_flags_for_spec : Set(String)
      compilation_flags.dup
    end
  end
end

describe Adamas::Compiler::CLI do
  {
    {"joined short flag", ["-Dcontract_feature"]},
    {"separated short flag", ["-D", "contract_feature"]},
    {"separated long flag", ["--define", "contract_feature"]},
    {"equals long flag", ["--define=contract_feature"]},
  }.each do |label, arguments|
    it "accepts a Crystal-compatible #{label}" do
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      cli = Adamas::Compiler::CLI.new(arguments + ["--version"])
      status = cli.run(out_io: out_io, err_io: err_io)

      status.should eq(0), err_io.to_s
      out_io.to_s.should contain("adamas ")
      err_io.to_s.should be_empty
      cli.compile_flags_for_spec.should contain("contract_feature")
      Adamas::Runtime.target_flags.should_not contain("contract_feature")
    end

    it "accepts a Crystal-compatible #{label} with the full option parser" do
      keys = {"ADAMAS_USE_OPTION_PARSER", "ADAMAS_SAFE_PARSER", "ADAMAS_MINIMAL_PARSER"}
      previous = keys.map { |key| {key, ENV[key]?} }
      begin
        ENV["ADAMAS_USE_OPTION_PARSER"] = "1"
        ENV.delete("ADAMAS_SAFE_PARSER")
        ENV.delete("ADAMAS_MINIMAL_PARSER")
        err_io = IO::Memory.new
        cli = Adamas::Compiler::CLI.new(arguments + ["--version"])
        cli.run(out_io: IO::Memory.new, err_io: err_io).should eq(0), err_io.to_s
        cli.compile_flags_for_spec.should contain("contract_feature")
        Adamas::Runtime.target_flags.should_not contain("contract_feature")
      ensure
        previous.each do |key, value|
          if value
            ENV[key] = value
          else
            ENV.delete(key)
          end
        end
      end
    end
  end

  it "keeps definitions isolated between sequential invocations" do
    first = Adamas::Compiler::CLI.new(["-Dfirst_contract_feature", "-Dsecond_contract_feature", "--version"])
    first.run(out_io: IO::Memory.new, err_io: IO::Memory.new).should eq(0)
    first.compile_flags_for_spec.should contain("first_contract_feature")
    first.compile_flags_for_spec.should contain("second_contract_feature")

    second = Adamas::Compiler::CLI.new(["--version"])
    second.run(out_io: IO::Memory.new, err_io: IO::Memory.new).should eq(0)
    second.compile_flags_for_spec.should_not contain("first_contract_feature")
    second.compile_flags_for_spec.should_not contain("second_contract_feature")
    Adamas::Runtime.target_flags.should_not contain("first_contract_feature")
    Adamas::Runtime.target_flags.should_not contain("second_contract_feature")
  end

  ["-D", "--define"].each do |argument|
    it "rejects a missing value for #{argument}" do
      err_io = IO::Memory.new
      status = Adamas::Compiler::CLI.new([argument]).run(out_io: IO::Memory.new, err_io: err_io)
      status.should eq(1)
      err_io.to_s.should contain("#{argument} expects a value")
    end
  end

  it "uses the same invocation flag in declaration, method and macro expansion" do
    source = <<-'CRYSTAL'
      {% if flag?(:contract_feature) %}
        def declared_flag : Int32
          101
        end
      {% else %}
        def declared_flag : Int32
          102
        end
      {% end %}

      macro expand_flag
        {% if flag?(:contract_feature) %}
          201
        {% else %}
          202
        {% end %}
      end

      def method_flag : Int32
        {% if flag?(:contract_feature) %}
          301
        {% else %}
          302
        {% end %}
      end

      def expanded_flag : Int32
        expand_flag
      end

      declared_flag
      method_flag
      expanded_flag
    CRYSTAL

    with_temp_shadow_project({"main.cr" => source}) do |dir|
      {true, false, true}.each_with_index do |defined, index|
        output = File.join(dir, "flags_#{index}")
        arguments = [File.join(dir, "main.cr"), "--no-prelude", "--emit", "hir", "--no-link",
                     "--no-ast-cache", "--no-llvm-cache", "-o", output]
        arguments << "-Dcontract_feature" if defined
        err_io = IO::Memory.new
        status = Adamas::Compiler::CLI.new(arguments).run(out_io: IO::Memory.new, err_io: err_io)
        status.should eq(0), err_io.to_s
        hir = File.read("#{output}.hir")
        {101, 201, 301}.each do |enabled_value|
          selected = defined ? enabled_value : enabled_value + 1
          rejected = defined ? enabled_value + 1 : enabled_value
          hir.should match(/literal #{selected} : Int32/)
          hir.should_not match(/literal #{rejected} : Int32/)
        end
      end
    end
  end

  it "does not load an inactive require branch when a flag is defined" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        {% if flag?(:contract_feature) %}
          require "./selected"
        {% else %}
          require "./missing_decoy"
        {% end %}
        flag_dependency
      CRYSTAL
      "selected.cr" => "def flag_dependency : Int32; 401; end\n",
    }) do |dir|
      output = File.join(dir, "require_flags")
      err_io = IO::Memory.new
      status = Adamas::Compiler::CLI.new([
        File.join(dir, "main.cr"), "-Dcontract_feature", "--no-prelude", "--emit", "hir",
        "--no-link", "--no-ast-cache", "--no-llvm-cache", "-o", output,
      ]).run(out_io: IO::Memory.new, err_io: err_io)
      status.should eq(0), err_io.to_s
      File.read("#{output}.hir").should match(/literal 401 : Int32/)
    end
  end

  it "derives the release macro flag from each invocation instead of a HIR default" do
    with_temp_shadow_project({"main.cr" => <<-'CRYSTAL'}) do |dir|
      def release_branch : Int32
        {% if flag?(:release) %}
          601
        {% else %}
          602
        {% end %}
      end
      release_branch
    CRYSTAL
      {
        {[] of String, 602},
        {["--release"], 601},
        {["-Drelease"], 601},
        {[] of String, 602},
      }.each_with_index do |(flags, selected), index|
        output = File.join(dir, "release_#{index}")
        arguments = [File.join(dir, "main.cr"), "--no-prelude", "--emit", "hir", "--no-link",
                     "--no-ast-cache", "--no-llvm-cache", "-o", output] + flags
        err_io = IO::Memory.new
        Adamas::Compiler::CLI.new(arguments).run(out_io: IO::Memory.new, err_io: err_io).should eq(0), err_io.to_s
        hir = File.read("#{output}.hir")
        hir.should match(/literal #{selected} : Int32/)
        hir.should_not match(/literal #{selected == 601 ? 602 : 601} : Int32/)
      end
    end
  end

  it "preserves host target flags without inventing optional HIR defaults" do
    names = ["bits64", "bits32", "little_endian", "big_endian", "darwin", "linux",
             "unix", "aarch64", "x86_64", "release", "preview_mt", "execution_context",
             "bootstrap_fast", "use_pcre2", "kqueue", "evloop=kqueue"]
    source = String.build do |io|
      names.each_with_index do |name, index|
        io << "def target_flag_#{index} : Int32\n"
        io << "  {% if flag?(#{name.inspect}) %}\n    #{1000 + index * 2}\n"
        io << "  {% else %}\n    #{1001 + index * 2}\n  {% end %}\nend\n"
        io << "target_flag_#{index}\n"
      end
    end
    with_temp_shadow_project({"main.cr" => source}) do |dir|
      output = File.join(dir, "host_flags")
      err_io = IO::Memory.new
      cli = Adamas::Compiler::CLI.new([
        File.join(dir, "main.cr"), "--no-prelude", "--emit", "hir", "--no-link",
        "--no-ast-cache", "--no-llvm-cache", "-o", output,
      ])
      cli.run(out_io: IO::Memory.new, err_io: err_io).should eq(0), err_io.to_s
      cli.compile_flags_for_spec.should eq(Adamas::Runtime.target_flags)
      hir = File.read("#{output}.hir")
      names.each_with_index do |name, index|
        enabled = Adamas::Runtime.target_flags.includes?(name)
        selected = 1000 + index * 2 + (enabled ? 0 : 1)
        rejected = 1000 + index * 2 + (enabled ? 1 : 0)
        hir.should match(/literal #{selected} : Int32/)
        hir.should_not match(/literal #{rejected} : Int32/)
      end
    end
  end
end
