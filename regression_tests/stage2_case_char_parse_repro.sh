#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_case_char_parse.XXXXXX")"

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
  local out="$WORKDIR/${name}.out"
  local wrapper="$WORKDIR/${name}.sh"

  printf '%s\n' "$body" >"$src"

  cat >"$wrapper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec env ADAMAS_STOP_AFTER_PARSE=1 "$COMPILER" --release --no-prelude "$src" -o "$out"
EOF
  chmod +x "$wrapper"

  set +e
  local output
  output="$("$ROOT_DIR/scripts/run_safe.sh" "$wrapper" 40 2048 2>&1)"
  local status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    echo "reproduced: $name still crashes during parse-only case/char handling"
    echo "$output" | tail -n 40
    exit 1
  fi
}

run_case "case_char_simple_in_def" $'def foo(x)\n  case x\n  when \'=\'\n    1\n  else\n    2\n  end\nend'
run_case "case_char_string_style_in_def" $'def foo(ptr)\n  case ptr.value.unsafe_chr\n  when \'-\'\n    ptr += 1\n  when \'+\'\n    ptr += 2\n  else\n    ptr += 3\n  end\nend'

echo "not reproduced: case/when with char literals parses correctly inside defs"
