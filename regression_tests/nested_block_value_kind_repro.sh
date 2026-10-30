#!/usr/bin/env bash
# Source kinds must survive aggregate fields and Proc signature slots even
# when an instance and its metaclass share one backend TypeRef carrier.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-${ADAMAS_BIN:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nested-block-value-kind.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK_DIR"/cache.*
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

python3 - "$WORK_DIR" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
cases = {
    "positive_tuple": """
def accepts(&block : -> Tuple(Foo.class | Int32, Bool))
  block.call
end
flag = true
accepts { {(if flag; Foo; else; 1; end), false} }
""",
    "positive_named_tuple": """
def accepts(&block : -> NamedTuple(item: Foo.class | Int32))
  block.call
end
flag = true
accepts { {item: (if flag; Foo; else; 1; end)} }
""",
    "positive_proc_output": """
def accepts(&block : -> Proc(Bool, Foo.class | Int32))
  block.call
end
accepts { ->(flag : Bool) { if flag; Foo; else; 1; end } }
""",
    "positive_proc_input": """
def accepts(&block : -> Proc(Foo.class | Int32, Bool))
  block.call
end
accepts { ->(value : Foo.class | Int32) { true } }
""",
    "positive_proc_call": """
callback = Proc(Foo.class | Int32, Nil).new { |value| nil }
callback.call(Foo)
callback.call(1)
""",
    "positive_proc_identity": """
def accepts(&block : -> Proc(Foo.class | Int32, Foo.class | Int32))
  block.call
end
accepts { ->(value : Foo.class | Int32) { value } }
""",
    "reject_tuple_collision": """
def accepts(&block : -> Tuple(Foo, Bool))
  block.call
end
flag = true
accepts { {(if flag; Foo; else; Foo.new; end), false} }
""",
    "reject_named_tuple_collision": """
def accepts(&block : -> NamedTuple(item: Foo))
  block.call
end
flag = true
accepts { {item: (if flag; Foo; else; Foo.new; end)} }
""",
    "reject_proc_output_collision": """
def accepts(&block : -> Proc(Bool, Foo))
  block.call
end
accepts { ->(flag : Bool) { if flag; Foo; else; Foo.new; end } }
""",
    "reject_proc_call_collision": """
callback = Proc(Foo.class | Int32, Nil).new { |value| nil }
callback.call(Foo.new)
""",
    "reject_proc_annotation_collision": """
callback = ->(flag : Bool) : Foo { if flag; Foo; else; Foo.new; end }
""",
}
prefix = """
class Foo
end
struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end

  def self.new(&block : self)
    block
  end
end
"""
for name, source in cases.items():
    (root / f"{name}.cr").write_text(prefix + source)
PY

stages=(original)
[[ "${ORIGINAL_ONLY:-0}" == 1 ]] || stages+=(candidate)
for stage in "${stages[@]}"; do
  for source in "$WORK_DIR"/*.cr; do
    name="$(basename "$source" .cr)"
    [[ -z "${ONLY_CASES:-}" || ",${ONLY_CASES}," == *",$name,"* ]] || continue
    status=0
    if [[ "$stage" == original ]]; then
      command=("$ORIGINAL" 180 8192 build --prelude=empty --no-codegen --no-debug)
    else
      command=("$COMPILER" 180 8192 --no-prelude --no-ast-cache --no-llvm-cache --emit hir --no-link)
    fi
    CRYSTAL_CACHE_DIR="$WORK_DIR/cache.$stage.$name" ADAMAS_LLVM_CACHE=0 \
      "$SAFE_RUNNER" "${command[@]}" "$source" -o "$WORK_DIR/$stage.$name" \
      >"$WORK_DIR/$stage.$name.log" 2>&1 || status=$?
    expected=0
    [[ "$name" != reject_* ]] || expected=1
    if [[ "$status" != "$expected" ]]; then
      cat "$WORK_DIR/$stage.$name.log" >&2
      echo "FAIL[$stage/$name]: expected semantic status $expected, got $status" >&2
      exit 1
    fi
    if [[ "$expected" == 1 ]]; then
      python3 - "$WORK_DIR/$stage.$name.log" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text().lower()
assert "error" in text, text
assert "syntax error" not in text and "parser errors" not in text, text
assert "internal compiler error" not in text and "unhandled exception" not in text, text
PY
    elif [[ "$stage" == candidate && ! -s "$WORK_DIR/$stage.$name.hir" ]]; then
      echo "FAIL[$stage/$name]: HIR lowering did not complete" >&2
      exit 1
    fi
    echo "PASS[$stage/$name]"
  done
done
