require "./semantic_cli_helpers"

include SemanticCliSpecHelpers

describe Adamas::Compiler::CLI do
  it "keeps same-file default-arg non-method macro-call declaration parity green" do
    with_temp_shadow_project({
      "main.cr" => <<-CR,
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

  it "keeps block-yield non-method macro-call declaration parity green" do
    with_temp_shadow_project({
      "main.cr" => <<-CR,
        macro define_bundle
          {{yield}}
        end

        define_bundle do
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

  it "keeps cross-file block-yield non-method macro-call declaration parity green" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        macro define_bundle
          {{yield}}
        end
      CR
      "main.cr" => <<-CR,
        require "./lib"
        define_bundle do
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

  it "keeps strict semantic shadow green when declaration parity matches" do
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

      with_semantic_shadow_strict_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      diagnostics = err_io.to_s
      output.should contain("declaration_gaps=0")
      output.should contain("Semantic shadow declarations: classes collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: modules collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: enums collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      output.should contain("Semantic shadow declarations: constants collector_total=1 collector_unique=1 semantic_total=1 semantic_unique=1 gaps=0")
      diagnostics.should_not contain("warning: semantic shadow failed:")
    end
  end

  it "counts generated overload families in shadow summaries" do
    with_temp_shadow_project({
      "main.cr" => <<-CR,
        def greet
        end

        macro define_greet(name)
          def greet(value : {{name.id}})
          end
        end

        define_greet(:Int32)
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
      output.should contain("semantic_direct_total=1")
      output.should contain("semantic_macro_expanded_total=1")
      output.should contain("generated_symbols=1")
    end
  end

  it "attributes generated overload families to the generated contributor unit" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        def greet
        end

        macro define_greet(name)
          def greet(value : {{name.id}})
          end
        end
      CR
      "main.cr" => <<-CR,
        require "./lib"
        define_greet(:Int32)
      CR
    }) do |dir|
      lib_path = File.join(dir, "lib.cr")
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new

      with_semantic_shadow_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        cli.run(out_io: out_io, err_io: err_io)
      end

      output = out_io.to_s
      lib_line = output.lines.find { |line| line.includes?("Semantic shadow unit: path=#{lib_path}") }
      main_line = output.lines.find { |line| line.includes?("Semantic shadow unit: path=#{main_path}") }

      lib_line.should_not be_nil
      main_line.should_not be_nil
      lib_line.not_nil!.should contain("generated_symbols=0")
      main_line.not_nil!.should contain("generated_symbols=1")
    end
  end

  it "reports non-method macro-expanded declaration provenance in shadow summaries" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        macro define_bundle
          class Alpha
          end

          module Beta
          end

          enum Delta
            One
          end

          GAMMA = 1
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
      output.should contain("generated_symbols=4")
      output.should contain("Semantic shadow declarations: classes provenance")
      output.should contain("Semantic shadow declarations: modules provenance")
      output.should contain("Semantic shadow declarations: enums provenance")
      output.should contain("Semantic shadow declarations: constants provenance")
      output.should contain("semantic_macro_expanded_total=1")
    end
  end

  it "reports macro-expanded macro declaration provenance in shadow summaries" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        macro define_trace
          macro generated_trace
          end
        end
      CR
      "main.cr" => <<-CR,
        require "./lib"
        define_trace
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
      output.should contain("generated_symbols=1")
      output.should contain("Semantic shadow declarations: macros provenance")
      output.should contain("semantic_direct_total=1")
      output.should contain("semantic_macro_expanded_total=1")
    end
  end

  it "preserves both direct and generated class provenance across reopenings" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        macro define_alpha
          class Alpha
          end
        end
      CR
      "main.cr" => <<-CR,
        require "./lib"
        define_alpha

        class Alpha
          def self.extra
          end
        end
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
      output.should contain("Semantic shadow declarations: classes provenance")
      output.should contain("semantic_direct_total=1")
      output.should contain("semantic_macro_expanded_total=1")
      output.should contain("generated_symbols=1")
    end
  end

  it "preserves both direct and generated module provenance across reopenings" do
    with_temp_shadow_project({
      "lib.cr" => <<-CR,
        macro define_alpha
          module Alpha
          end
        end
      CR
      "main.cr" => <<-CR,
        require "./lib"
        define_alpha

        module Alpha
          VALUE = 1
        end
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
      output.should contain("Semantic shadow declarations: modules provenance")
      output.should contain("semantic_direct_total=1")
      output.should contain("semantic_macro_expanded_total=1")
      output.should contain("generated_symbols=1")
    end
  end

  it "prints macro definition note for cross-file generated diagnostics" do
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

      diagnostics = err_io.to_s
      diagnostics.should contain("note: expanded from macro call here")
      diagnostics.should contain("note: macro defined here")
      diagnostics.should contain(File.join(dir, "lib.cr"))
    end
  end

  it "prints macro definition note for cross-file generated type diagnostics" do
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

      diagnostics = err_io.to_s
      diagnostics.should contain("error[E3001]")
      diagnostics.should contain("[generated]")
      diagnostics.should contain("note: expanded from macro call here")
      diagnostics.should contain("note: macro defined here")
      diagnostics.should contain(File.join(dir, "lib.cr"))
    end
  end

  it "does not print redundant macro definition note for same-file generated diagnostics" do
    with_temp_shadow_project({
      "main.cr" => <<-CR,
        macro define_bad(name)
          def {{name.id}}
            missing + 1
          end
        end

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

      diagnostics = err_io.to_s
      diagnostics.should contain("note: expanded from macro call here")
      diagnostics.should_not contain("note: macro defined here")
    end
  end

  it "does not print redundant macro definition note for same-file generated type diagnostics" do
    with_temp_shadow_project({
      "main.cr" => <<-CR,
        macro define_bad(name)
          def {{name.id}}
            1 + "x"
          end
        end

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

      diagnostics = err_io.to_s
      diagnostics.should contain("error[E3001]")
      diagnostics.should contain("[generated]")
      diagnostics.should contain("note: expanded from macro call here")
      diagnostics.should_not contain("note: macro defined here")
    end
  end

  it "keeps semantic compile prepass green for stdlib class_property macros" do
    with_temp_shadow_project({
      "main.cr" => <<-CRYSTAL,
        require #{File.expand_path("../src/stdlib/object/properties", __DIR__).inspect}

        class Reference < Object
        end

        struct Time
        end

        class Time::Location < Reference
          class_property(local : Location) { self }
        end

        Time::Location.local
      CRYSTAL
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0)
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end
end
