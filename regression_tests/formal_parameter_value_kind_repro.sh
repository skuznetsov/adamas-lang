#!/usr/bin/env bash
# A formal's name cannot turn an instance into a class object during specialization.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
stock="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
candidate="${1:-${ADAMAS_BIN:-$root/bin/adamas}}"
safe="$root/scripts/run_safe.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/formal-value-kind.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export CRYSTAL_CACHE_DIR="$work/cache" RUN_SAFE_PASSTHROUGH_STDIO=1
link=()
if [[ "$(uname -s)" == Darwin ]]; then
  link=(--link-flags=-fuse-ld=/usr/bin/ld)
fi
printf 'FTFTCIICCI\n' > "$work/expected"
cat > "$work/instance.cr" <<'CR'
struct Token
end
class Sink
  def initialize(value : Token.class)
  end
end
def forward(token_class)
  Sink.new(token_class)
end
forward(Token.new)
CR
sed -e 's/value : Token.class/value : Token/' -e 's/forward(Token.new)/forward(Token)/' "$work/instance.cr" > "$work/class.cr"

for mode in stock adamas; do
  if [[ "$mode" == stock ]]; then
    compile=("$safe" "$stock" 120 4096 build --prelude=empty "${link[@]}")
  else
    compile=("$safe" "$candidate" 120 4096 --no-prelude --no-ast-cache --no-llvm-cache)
  fi
  if ! "${compile[@]}" "$root/regression_tests/formal_parameter_value_kind_repro.cr" -o "$work/$mode" > "$work/build.log" 2>&1; then
    cat "$work/build.log" >&2
    exit 1
  fi
  "$safe" "$work/$mode" 8 512 > "$work/output" 2> "$work/run.log" || { cat "$work/run.log" >&2; exit 1; }
  cmp "$work/expected" "$work/output"
  for kind in instance class; do
    rc=0
    "${compile[@]}" "$work/$kind.cr" -o "$work/$mode-$kind" > "$work/bad.log" 2>&1 || rc=$?
    if [[ "$rc" -ne 1 ]] || [[ -e "$work/$mode-$kind" ]] || ! grep -Eiq 'error:.*(no overload matches Sink\.new|expected argument .*Sink\.new).*Token' "$work/bad.log"; then
      echo "$mode returned $rc for the invalid $kind argument" >&2
      cat "$work/bad.log" >&2
      exit 1
    fi
  done
  echo "$mode passed formal value kinds and both constructor rejections"
done
