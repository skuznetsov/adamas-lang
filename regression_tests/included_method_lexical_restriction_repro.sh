#!/usr/bin/env bash
# Included methods keep their declaration namespace when checking restrictions.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
safe="$root/scripts/run_safe.sh"
adamas="${COMPILER:-${1:-$root/bin/adamas}}"
crystal="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld -L/opt/homebrew/lib -lgc}"
export ADAMAS_LLVM_CACHE=0
tmp="$(mktemp -d "${TMPDIR:-/tmp}/included-method-lexical-restriction.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

cat >prefix.cr <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

module HTTP
  class Server
    class Context
    end
  end

  module Handler
    def call_next(context : HTTP::Server::Context) : Nil
      LibC.exit(0)
    end
  end
end

module App::HTTP
  class Server
    class Context
    end
  end

  module Router
    include ::HTTP::Handler

    alias Action = Proc(::HTTP::Server::Context, Int32, ::HTTP::Server::Context)

    def get(path : Int32, &block : Action)
      block.call(::HTTP::Server::Context.new, path)
    end
  end

  class ViewsController
    include Router

    macro static_view
      get(7) do |context, path|
        call_next(context)
        context
      end
    end

    def initialize
CRYSTAL
cat >suffix.cr <<'CRYSTAL'
    end
  end
end

App::HTTP::ViewsController.new
LibC.exit(11)
CRYSTAL

fixture() {
  { cat prefix.cr; printf '      %s\n' "$2"; cat suffix.cr; } >"$1.cr"
}
fixture block 'static_view'
fixture direct 'call_next(::HTTP::Server::Context.new)'
fixture named 'call_next(context: ::HTTP::Server::Context.new)'
fixture shadow 'call_next(Server::Context.new)'
fixture named_shadow 'call_next(context: Server::Context.new)'

cat >direct_scope.cr <<'CRYSTAL'
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Receiver
  class Token
  end

  def consume(x : Token) : Int32
    7
  end
end

module CallerScope
  class Token
  end

  def call(receiver : Receiver, token)
    receiver.consume(token)
  end
end

class Host
  include CallerScope
end

LibC.exit(Host.new.call(Receiver.new, Receiver::Token.new) == 7 ? 0 : 11)
CRYSTAL
sed 's/Receiver::Token.new/CallerScope::Token.new/' direct_scope.cr >direct_scope_shadow.cr

check() {
  local mode="$1" fixture output log
  shift
  for fixture in block direct named shadow named_shadow direct_scope direct_scope_shadow; do
    output="$fixture.$mode"
    log="$output.compile.log"
    if [[ "$fixture" == *shadow ]]; then
      local wrong_type='App::HTTP::Server::Context' method=call_next
      if [[ "$fixture" == direct_scope_shadow ]]; then
        wrong_type='CallerScope::Token'
        method=consume
      fi
      if "$safe" "$@" --prelude=empty "$fixture.cr" -o "$output" >"$log" 2>&1 ||
         ! rg -q '\[EXIT: 1\]' "$log" ||
         ! rg -q "no overload matches .*#$method|expected argument .*#$method" "$log" ||
         ! rg -q "$wrong_type" "$log" ||
         [[ -e "$output" ]]; then
        echo "FAIL $output rejection" >&2
        cat "$log" >&2
        return 1
      fi
    else
      "$safe" "$@" --prelude=empty "$fixture.cr" -o "$output" >"$log" 2>&1 ||
        { echo "FAIL $output compile" >&2; cat "$log" >&2; return 1; }
      "$safe" "$tmp/$output" 5 512 >"$output.run.log" 2>&1 ||
        { echo "FAIL $output runtime" >&2; cat "$output.run.log" >&2; return 1; }
    fi
  done
}

check stock "$crystal" 60 4096 build
ADAMAS_EAGER_HIR=0 check lazy "$adamas" 60 4096
ADAMAS_EAGER_HIR=1 check eager "$adamas" 60 4096

echo 'PASS included method lexical restrictions (21 stock, lazy, and eager checks)'
