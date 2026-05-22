#!/usr/bin/env crystal

require "./compiler/bootstrap_shims"
require "./compiler/lsp/tool_dispatch"
require "./compiler/cli"

{% if flag?(:darwin) %}
  @[Link(ldflags: "-Wl,-stack_size,0x4000000")]
  lib LibC
  end
{% end %}

trace_bootstrap = CrystalV2::Compiler::BootstrapEnv.get?("STAGE2_BOOTSTRAP_TRACE") == "1"

begin
  if CrystalV2::Compiler::LSP::ToolDispatch.tool_lsp?(ARGV)
    exit CrystalV2::Compiler::LSP::ToolDispatch.exec_lsp(ARGV)
  end

  STDERR.puts "[BOOTSTRAP_TRACE] main: cli.new" if trace_bootstrap
  cli = CrystalV2::Compiler::CLI.new(ARGV)
  STDERR.puts "[BOOTSTRAP_TRACE] main: cli.run" if trace_bootstrap
  exit_code = cli.run
  STDERR.puts "[BOOTSTRAP_TRACE] main: exit_code=#{exit_code}" if trace_bootstrap
  exit exit_code
rescue ex
  if trace_bootstrap
    STDERR.puts "[BOOTSTRAP_TRACE] main: exception=#{ex.class} message=#{ex.message.inspect}"
    if bt = ex.backtrace?
      bt.each { |line| STDERR.puts "[BOOTSTRAP_TRACE]   #{line}" }
    end
  end
  raise ex
end
