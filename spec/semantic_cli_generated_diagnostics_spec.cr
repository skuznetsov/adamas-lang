require "./semantic_cli_helpers"

include SemanticCliSpecHelpers

describe Adamas::Compiler::CLI do
  it "reports compile and shadow parse diagnostics separately in semantic shadow summaries" do
    with_temp_shadow_project({
      "main.cr" => ")\n",
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      output.should contain("Semantic shadow:")
      output.should contain("compile_parse_diags=1")
      output.should contain("shadow_parse_diags=1")
      output.should contain("parse_diag_gaps=0")
      output.should contain("Semantic shadow parse diagnostics: compile_total=1 compile_unique=1 shadow_total=1 shadow_unique=1 gaps=0")
      output.should contain("Semantic shadow unit: path=#{main_path}")
    end
  end

  it "keeps strict semantic shadow green when parse parity matches" do
    with_temp_shadow_project({
      "main.cr" => ")\n",
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_strict_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      diagnostics = err_io.to_s
      output.should contain("parse_diag_gaps=0")
      output.should contain("Semantic shadow parse diagnostics: compile_total=1 compile_unique=1 shadow_total=1 shadow_unique=1 gaps=0")
      diagnostics.should_not contain("warning: semantic shadow failed:")
    end
  end

  it "reports generated resolution diagnostics separately in semantic shadow summaries" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        macro define_bad(name)
          def {{name.id}}
            missing + 1
          end
        end
      CR
      "main.cr" => <<-CR,
        require "./lib"
        define_bad(:alpha)
        alpha()
      CR
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      output.should contain("Semantic shadow:")
      output.should contain("generated_resolution_diags=1")
      output.should contain("generated_type_diags=1")
      output.should contain("Semantic shadow unit: path=#{main_path}")
    end
  end

  it "reports generated type diagnostics separately in semantic shadow summaries" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        macro define_bad(name)
          def {{name.id}}
            1 + "x"
          end
        end
      CR
      "main.cr" => <<-CR,
        require "./lib"
        define_bad(:alpha)
        alpha()
      CR
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      output.should contain("Semantic shadow:")
      output.should contain("generated_resolution_diags=0")
      output.should contain("generated_type_diags=1")
      output.should contain("Semantic shadow unit: path=#{main_path}")
    end
  end

  it "reports generated diagnostics inside macro-expanded class bodies" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        macro define_bad_class
          class BadBox
            def self.call
              missing + 1
            end
          end
        end
      CR
      "main.cr" => <<-CR,
        require "./lib"
        define_bad_class
        BadBox.call
      CR
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      diagnostics = err_io.to_s
      output.should contain("generated_resolution_diags=1")
      output.should contain("generated_type_diags=1")
      output.should contain("Semantic shadow unit: path=#{main_path}")
      diagnostics.should contain("BadBox")
      diagnostics.should contain("missing + 1")
      diagnostics.should contain("note: expanded from macro call here")
    end
  end

  it "reports semantic declaration provenance for macro-expanded methods" do
    with_temp_shadow_project({
      "main.cr" => <<-CR,
        def direct_greet
        end

        macro define_alpha
          def alpha
          end
        end

        define_alpha
      CR
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      output.should contain("Semantic shadow declarations: methods provenance")
      output.should contain("semantic_direct_total=1")
      output.should contain("semantic_macro_expanded_total=1")
      output.should contain("generated_symbols=1")
    end
  end

  it "keeps non-method macro-call declaration parity green" do
    with_temp_shadow_project({
      "main.cr" => <<-CR,
        macro define_bundle
          class Alpha
          end

          module Beta
          end

          enum Mode
            One
          end

          FLAG = 1
        end

        define_bundle
      CR
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      output.should contain("declaration_gaps=0")
      output.should contain("Semantic shadow declarations: classes collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: modules collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: enums collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: constants collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: classes provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: classes provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
    end
  end

  it "keeps cross-file non-method macro-call declaration parity green" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        macro define_bundle
          class Alpha
          end

          module Beta
          end

          enum Mode
            One
          end

          FLAG = 1
        end
      CR
      "main.cr" => <<-CR,
        require "./lib"
        define_bundle
      CR
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      output.should contain("declaration_gaps=0")
      output.should contain("Semantic shadow declarations: classes collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: modules collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: enums collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: constants collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: classes provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: classes provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
    end
  end

  it "keeps argful non-method macro-call declaration parity green" do
    with_temp_shadow_project({
      "main.cr" => <<-CR,
        macro define_bundle(class_name, module_name, enum_name, const_name)
          class {{class_name.id}}
          end

          module {{module_name.id}}
          end

          enum {{enum_name.id}}
            One
          end

          {{const_name.id}} = 1
        end

        define_bundle(:Alpha, :Beta, :Mode, :FLAG)
      CR
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      output.should contain("declaration_gaps=0")
      output.should contain("Semantic shadow declarations: classes collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: modules collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: enums collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: constants collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: classes provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: classes provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
    end
  end

  it "keeps cross-file argful non-method macro-call declaration parity green" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        macro define_bundle(class_name, module_name, enum_name, const_name)
          class {{class_name.id}}
          end

          module {{module_name.id}}
          end

          enum {{enum_name.id}}
            One
          end

          {{const_name.id}} = 1
        end
      CR
      "main.cr" => <<-CR,
        require "./lib"
        define_bundle(:Alpha, :Beta, :Mode, :FLAG)
      CR
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      output.should contain("declaration_gaps=0")
      output.should contain("Semantic shadow declarations: classes collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: modules collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: enums collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: constants collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: classes provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: classes provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
    end
  end

  it "keeps named-arg non-method macro-call declaration parity green" do
    with_temp_shadow_project({
      "main.cr" => <<-CR,
        macro define_bundle(class_name, module_name, enum_name, const_name)
          class {{class_name.id}}
          end

          module {{module_name.id}}
          end

          enum {{enum_name.id}}
            One
          end

          {{const_name.id}} = 1
        end

        define_bundle(class_name: :Alpha, module_name: :Beta, enum_name: :Mode, const_name: :FLAG)
      CR
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      output.should contain("declaration_gaps=0")
      output.should contain("Semantic shadow declarations: classes collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: modules collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: enums collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: constants collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: classes provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: classes provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
    end
  end

  it "keeps cross-file named-arg non-method macro-call declaration parity green" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        macro define_bundle(class_name, module_name, enum_name, const_name)
          class {{class_name.id}}
          end

          module {{module_name.id}}
          end

          enum {{enum_name.id}}
            One
          end

          {{const_name.id}} = 1
        end
      CR
      "main.cr" => <<-CR,
        require "./lib"
        define_bundle(class_name: :Alpha, module_name: :Beta, enum_name: :Mode, const_name: :FLAG)
      CR
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      output.should contain("declaration_gaps=0")
      output.should contain("Semantic shadow declarations: classes collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: modules collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: enums collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: constants collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: classes provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: classes provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
    end
  end

  it "keeps default-arg cross-file non-method macro-call declaration parity green" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        macro define_bundle(class_name = :Alpha, module_name = :Beta, enum_name = :Mode, const_name = :FLAG)
          class {{class_name.id}}
          end

          module {{module_name.id}}
          end

          enum {{enum_name.id}}
            One
          end

          {{const_name.id}} = 1
        end
      CR
      "main.cr" => <<-CR,
        require "./lib"
        define_bundle
      CR
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      output.should contain("declaration_gaps=0")
      output.should contain("Semantic shadow declarations: classes collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: modules collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: enums collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: constants collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: classes provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: classes provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: modules provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: enums provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance collector_direct_total=0 collector_direct_unique=0 collector_macro_expanded_total=1 collector_macro_expanded_unique=1")
      output.should contain("Semantic shadow declarations: constants provenance semantic_direct_total=0 semantic_direct_unique=0 semantic_macro_expanded_total=1 semantic_macro_expanded_unique=1")
    end
  end
end
