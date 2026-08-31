require "./semantic_cli_helpers"

include SemanticCliSpecHelpers

describe Adamas::Compiler::CLI do
  it "keeps stage2 debug output silent by default and honors existing trace flags" do
    trace_keys = ["STAGE2_DEBUG", "STAGE2_BOOTSTRAP_TRACE", "ADAMAS_STAGE2_DEBUG", "ADAMAS_TRACE_STDERR"]
    previous = {} of String => String?
    trace_keys.each do |key|
      previous[key] = ENV[key]?
      ENV.delete(key)
    end

    begin
      quiet_out = IO::Memory.new
      quiet_err = IO::Memory.new
      Adamas::Compiler::CLI.new(["--version"]).run(out_io: quiet_out, err_io: quiet_err).should eq(0)
      quiet_err.to_s.should be_empty

      trace_keys.each do |key|
        ENV[key] = "1"
        trace_out = IO::Memory.new
        trace_err = IO::Memory.new
        Adamas::Compiler::CLI.new(["--version"]).run(out_io: trace_out, err_io: trace_err).should eq(0)
        trace_err.to_s.should contain("[STAGE2_DEBUG]")
        ENV.delete(key)
      end
    ensure
      trace_keys.each do |key|
        if value = previous[key]
          ENV[key] = value
        else
          ENV.delete(key)
        end
      end
    end
  end

  it "reports semantic errors when --no-codegen is used" do
    file_path = File.join(__DIR__, "semantic/test_data/missing_method.cr")
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    cli = Adamas::Compiler::CLI.new([file_path, "--no-codegen"])
    cli.run(out_io: out_io, err_io: err_io)

    err_io.rewind
    diag = err_io.gets_to_end
    diag.should contain("undefined local variable or method 'say_hello'")
  end

  it "dumps nested scopes when --dump-symbols is used" do
    file_path = File.join(__DIR__, "semantic/test_data/nested_symbols.cr")
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    cli = Adamas::Compiler::CLI.new([file_path, "--dump-symbols", "--no-codegen"])
    cli.run(out_io: out_io, err_io: err_io)

    err_io.rewind
    err_io.to_s.should be_empty

    out_io.rewind
    output = out_io.gets_to_end
    output.should contain("class Greeter")
    output.should contain("  method greet (params: name)")
    output.should contain("    variable name")
  end

  it "emits semantic diagnostics for incompatible redefinitions with --no-codegen" do
    file_path = File.join(__DIR__, "semantic/test_data/incompatible_redefinition.cr")
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    cli = Adamas::Compiler::CLI.new([file_path, "--no-codegen"])
    cli.run(out_io: out_io, err_io: err_io)

    err_io.rewind
    diagnostics = err_io.gets_to_end
    diagnostics.should contain("error[E2001]")
    diagnostics.should contain("cannot redefine class 'Thing' as method")
    diagnostics.should contain("previous class defined here")
  end

  it "emits E2003 error for class reopening with different superclass" do
    file_path = File.join(__DIR__, "semantic/test_data/superclass_mismatch.cr")
    out_io = IO::Memory.new
    err_io = IO::Memory.new

    cli = Adamas::Compiler::CLI.new([file_path, "--no-codegen"])
    cli.run(out_io: out_io, err_io: err_io)

    err_io.rewind
    diagnostics = err_io.gets_to_end
    diagnostics.should contain("error[E2003]")
    diagnostics.should contain("class 'Foo' already defined with superclass 'Bar'")
    diagnostics.should contain("previous superclass declared here")
  end

  it "runs semantic compile prepass on the real compile path before lowering" do
    with_temp_shadow_project({
      "main.cr" => "1\n",
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
      out_io.to_s.should contain("Semantic compile prepass:")
      out_io.to_s.should contain("compile_parse_diags=0")
      out_io.to_s.should contain("shadow_parse_diags=0")
      out_io.to_s.should contain("parse_diag_gaps=0")
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "hands same-arena semantic overload targets to production HIR lowering" do
    with_temp_shadow_project({
      "main.cr" => [
        "class SemanticCliRoute",
        "def route(value) : String",
        %("wrong"),
        "end",
        "def route(value : Int32)",
        "self.route(value)",
        "end",
        "end",
        "SemanticCliRoute.new.route(1)",
      ].join('\n'),
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      hir_path = "#{output_path}.hir"
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([
          main_path,
          "--no-prelude",
          "--stats",
          "--verbose",
          "--emit", "hir",
          "--no-link",
          "-o", output_path,
        ])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0), err_io.to_s
      out_io.to_s.should contain("Semantic call targets: same-arena")
      hir = File.read(hir_path)
      hir.should contain("SemanticCliRoute#route$Int32")
      hir.should_not contain(%("wrong"))
    end
  end

  it "hands semantic targets when every additional parsed unit is inactive" do
    with_temp_shadow_project({
      "main.cr" => [
        %(require "./inactive"),
        "class SemanticCliMultiRoute",
        "def route(value) : String",
        %("wrong"),
        "end",
        "def route(value : Int32)",
        "self.route(value)",
        "end",
        "end",
        "SemanticCliMultiRoute.new.route(1)",
      ].join('\n'),
      "inactive.cr" => "{% skip_file %}\n",
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      hir_path = "#{output_path}.hir"
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([
          main_path,
          "--no-prelude",
          "--stats",
          "--verbose",
          "--emit", "hir",
          "--no-link",
          "-o", output_path,
        ])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0), err_io.to_s
      out_io.to_s.should contain("Semantic call targets: same-arena")
      hir = File.read(hir_path)
      hir.should contain("SemanticCliMultiRoute#route$Int32")
      hir.should_not contain(%("wrong"))
    end
  end

  it "does not hand semantic targets across multiple active arenas" do
    with_temp_shadow_project({
      "main.cr" => [
        %(require "./active"),
        "SemanticCliActiveDependency.new.value",
      ].join('\n'),
      "active.cr" => [
        "class SemanticCliActiveDependency",
        "def value",
        "1",
        "end",
        "end",
      ].join('\n'),
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 1

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([
          main_path,
          "--no-prelude",
          "--stats",
          "--verbose",
          "--emit", "hir",
          "--no-link",
          "-o", output_path,
        ])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(0), err_io.to_s
      out_io.to_s.should_not contain("Semantic call targets: same-arena")
    end
  end

  it "fails compile early on semantic compile prepass resolution errors" do
    with_temp_shadow_project({
      "main.cr" => "missing + 1\n",
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 0

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(1)
      out_io.to_s.should contain("Semantic compile prepass:")
      out_io.to_s.should contain("compile_parse_diags=0")
      out_io.to_s.should contain("shadow_parse_diags=0")
      out_io.to_s.should contain("parse_diag_gaps=0")
      out_io.to_s.should contain("resolution_diags=1")
      diagnostics = err_io.to_s
      diagnostics.should contain("undefined local variable or method 'missing'")
      diagnostics.should contain("error: compilation failed due to semantic compile prepass errors")
    end
  end

  it "fails compile early on semantic compile prepass type errors" do
    with_temp_shadow_project({
      "main.cr" => "1 + \"x\"\n",
    }) do |dir|
      main_path = File.join(dir, "main.cr")
      output_path = File.join(dir, "main")
      out_io = IO::Memory.new
      err_io = IO::Memory.new
      status = 0

      with_semantic_compile_env do
        cli = Adamas::Compiler::CLI.new([main_path, "--no-prelude", "--stats", "--verbose", "--no-link", "-o", output_path])
        status = cli.run(out_io: out_io, err_io: err_io)
      end

      status.should eq(1)
      out_io.to_s.should contain("Semantic compile prepass:")
      out_io.to_s.should contain("compile_parse_diags=0")
      out_io.to_s.should contain("shadow_parse_diags=0")
      out_io.to_s.should contain("parse_diag_gaps=0")
      out_io.to_s.should contain("type_diags=1")
      diagnostics = err_io.to_s
      diagnostics.should contain("error[E3001]")
      diagnostics.should contain("Operator '+' not defined for Int32 and String")
      diagnostics.should contain("error: compilation failed due to semantic compile prepass errors")
    end
  end

  it "keeps semantic compile prepass green when compile and aggregate parse diagnostics match" do
    with_temp_shadow_project({
      "main.cr" => ")\n",
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
      output = out_io.to_s
      diagnostics = err_io.to_s
      output.should contain("Semantic compile prepass:")
      output.should contain("compile_parse_diags=1")
      output.should contain("shadow_parse_diags=1")
      output.should contain("parse_diag_gaps=0")
      diagnostics.should_not contain("semantic shadow strict parse diagnostic mismatch")
      diagnostics.should_not contain("error: compilation failed due to semantic compile aggregate parser errors")
    end
  end

  it "keeps semantic compile prepass green for variadic macro params" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        macro build(*properties)
          {% for property in properties %}
            class {{property.id}}
            end
          {% end %}
        end

        build Foo, Bar
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
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps compile-path macro reflection green for skip_file and has_constant? branches" do
    with_temp_shadow_project({
      "event_loop.cr" => <<-'CRYSTAL',
        abstract class Crystal::EventLoop
        end

        {% if flag?(:wasi) %}
          class Crystal::EventLoop::Wasi < Crystal::EventLoop
          end
        {% elsif flag?(:unix) %}
          {% if flag?("evloop=libevent") %}
            class Crystal::EventLoop::LibEvent < Crystal::EventLoop
            end
          {% elsif flag?("evloop=epoll") || flag?(:android) || flag?(:linux) %}
            abstract class Crystal::EventLoop::Polling < Crystal::EventLoop
            end
          {% elsif flag?("evloop=kqueue") || flag?(:darwin) || flag?(:freebsd) %}
            abstract class Crystal::EventLoop::Polling < Crystal::EventLoop
            end
          {% else %}
            class Crystal::EventLoop::LibEvent < Crystal::EventLoop
            end
          {% end %}
        {% elsif flag?(:win32) %}
          class Crystal::EventLoop::IOCP < Crystal::EventLoop
          end
        {% end %}
      CRYSTAL
      "evented.cr" => <<-'CRYSTAL',
        require "./event_loop"

        {% skip_file unless flag?(:wasi) || Crystal::EventLoop.has_constant?(:LibEvent) %}

        module IO::Evented
          VALUE = 1
        end
      CRYSTAL
      "fd.cr" => <<-'CRYSTAL',
        class IO
        end

        require "./evented"

        module Crystal::System::FileDescriptor
          {% if IO.has_constant?(:Evented) %}
            VALUE = IO::Evented::VALUE
          {% else %}
            VALUE = 0
          {% end %}
        end
      CRYSTAL
      "socket.cr" => <<-'CRYSTAL',
        require "./fd"

        module Crystal::System::Socket
          {% if Crystal::EventLoop.has_constant?(:Polling) %}
            VALUE = Crystal::EventLoop::Polling
          {% else %}
            VALUE = 0
          {% end %}
        end
      CRYSTAL
      "main.cr" => <<-'CRYSTAL',
        require "./socket"

        Crystal::System::FileDescriptor::VALUE
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
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "retains the active require from nested macro conditionals with string flags" do
    with_temp_shadow_project({
      "event_loop.cr" => <<-'CRYSTAL',
        {% if flag?(:unix) %}
          {% if flag?("evloop=libevent") %}
            require "./libevent"
          {% elsif flag?("evloop=epoll") || flag?(:android) || flag?(:linux) %}
            require "./epoll"
          {% elsif flag?("evloop=kqueue") || flag?(:darwin) || flag?(:freebsd) %}
            require "./kqueue"
          {% else %}
            require "./fallback"
          {% end %}
        {% elsif flag?(:win32) %}
          require "./iocp"
        {% end %}
      CRYSTAL
      "libevent.cr" => "module NestedRequireProbe\n  VALUE = :libevent\nend\n",
      "epoll.cr" => "module NestedRequireProbe\n  VALUE = :epoll\nend\n",
      "kqueue.cr" => "module NestedRequireProbe\n  VALUE = :kqueue\nend\n",
      "fallback.cr" => "module NestedRequireProbe\n  VALUE = :fallback\nend\n",
      "iocp.cr" => "module NestedRequireProbe\n  VALUE = :iocp\nend\n",
      "main.cr" => <<-'CRYSTAL',
        require "./event_loop"
        NestedRequireProbe::VALUE
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

      expected_branch = if Adamas::Runtime.target_flags.includes?("darwin") || Adamas::Runtime.target_flags.includes?("freebsd")
                          "kqueue"
                        elsif Adamas::Runtime.target_flags.includes?("linux") || Adamas::Runtime.target_flags.includes?("android")
                          "epoll"
                        elsif Adamas::Runtime.target_flags.includes?("win32")
                          "iocp"
                        else
                          "fallback"
                        end
      output = out_io.to_s
      status.should eq(0)
      output.should contain("Loading: #{File.join(dir, "#{expected_branch}.cr")}")
      ["libevent", "epoll", "kqueue", "fallback", "iocp"].each do |branch|
        next if branch == expected_branch
        output.should_not contain("Loading: #{File.join(dir, "#{branch}.cr")}")
      end
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for hash-backed macro iteration and mutation" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        {% begin %}
          {% properties = {} of Nil => Nil %}
          {% properties["Foo".id] = {key: "Bar".id.stringify} %}
          {% for name, value in properties %}
            class {{name.id}}
            end

            class {{value[:key].id}}
            end
          {% end %}
        {% end %}
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
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for top-level begin macros with nested branch text and later macro defs" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        {% begin %}
        def spawn(same_thread = false)
          {% if flag?(:execution_context) %}
            1
          {% else %}
            value = 1
            {% if flag?(:preview_mt) %} value = 2 if same_thread {% end %}
            value
          {% end %}
        end
        {% end %}

        macro spawn(call)
          {{call}}
        end

        spawn(spawn(false))
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
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for top-level macro if without begin wrapper and later macro defs" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        {% if flag?(:darwin) %}
        def choose
          1
        end
        {% else %}
        def choose
          2
        end
        {% end %}

        macro wrap(call)
          {{call}}
        end

        wrap(choose)
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
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for top-level macro if raw-text stitching with comment and string markers" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        {% if flag?(:darwin) %}
        def choose
          text = "alpha {% not a macro %}"
          # {% ignored %}
          text
        end
        {% else %}
        def choose
          text = "beta {% not a macro %}"
          # {% ignored %}
          text
        end
        {% end %}

        macro wrap(call)
          {{call}}
        end

        wrap(choose)
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
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end

  it "keeps semantic compile prepass green for nested top-level macro control literals without expander-only features" do
    with_temp_shadow_project({
      "main.cr" => <<-'CRYSTAL',
        {% if flag?(:unix) %}
          {% if flag?(:bsd) %}
            def host_impl
              1
            end
          {% else %}
            def host_impl
              2
            end
            {% if flag?(:linux) %}
              def linux_impl
                3
              end
            {% end %}
          {% end %}
        {% elsif flag?(:win32) %}
          def host_impl
            4
          end
        {% else %}
          def host_impl
            5
          end
        {% end %}

        host_impl
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
      out_io.to_s.should contain("semantic_diags=0")
      out_io.to_s.should contain("resolution_diags=0")
      out_io.to_s.should contain("type_diags=0")
      err_io.to_s.should be_empty
    end
  end
end
