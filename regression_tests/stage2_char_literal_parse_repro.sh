#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_char_literal_parse.XXXXXX")"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found/executable: $COMPILER" >&2
  exit 2
fi

run_case() {
  local name="$1"
  local body="$2"
  local src="$WORKDIR/${name}.cr"
  local out="$WORKDIR/${name}.bin"
  local wrapper="$WORKDIR/${name}.sh"

  printf '%s\n' "$body" >"$src"

  cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$COMPILER" --release --no-prelude "$src" -o "$out"
EOF
  chmod +x "$wrapper"

  set +e
  local output
  output="$("$ROOT_DIR/scripts/run_safe.sh" "$wrapper" 60 2048 2>&1)"
  local status=$?
  set -e

  if [[ $status -ne 0 || ! -x "$out" ]]; then
    echo "reproduced: $name still crashes or fails during char literal compilation"
    echo "$output" | tail -n 40
    exit 1
  fi
}

run_case "char_toplevel" "'='"
run_case "char_call_arg" $'class Probe\n  def self.hit(x)\n    x\n  end\nend\n\nProbe.hit(\'=\')'
run_case "char_macro_call" $'class Object\n  macro delegate\n    {% if hit(\'=\') %}\n      1\n    {% else %}\n      2\n    {% end %}\n  end\n\n  def self.hit(x)\n    x\n  end\nend\n\n1'
run_case "char_escape_newline" $"'\\n'"
run_case "char_escape_unicode" $"'\\u{41}'"

echo "not reproduced: char literals parse and compile across direct, call-arg, macro, and escape cases"
