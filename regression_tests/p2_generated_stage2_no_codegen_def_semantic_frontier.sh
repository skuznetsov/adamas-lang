#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <generated-stage2-compiler>" >&2
  exit 2
fi

compiler="$1"
if [[ ! -x "$compiler" ]]; then
  echo "compiler is not executable: $compiler" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/cv2_no_codegen_def_semantic.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

write_case() {
  local name="$1"
  local path="$tmp_dir/$name.cr"
  case "$name" in
    bare_def)
      cat >"$path" <<'CR'
struct Foo
  def call
  end
end
CR
      ;;
    untyped_param)
      cat >"$path" <<'CR'
struct Foo
  def call(arg)
  end
end
CR
      ;;
    typed_param)
      cat >"$path" <<'CR'
struct Foo
  def call(arg : Int32)
  end
end
CR
      ;;
    return_annotation)
      cat >"$path" <<'CR'
struct Foo
  def call : Int32
  end
end
CR
      ;;
    splat_param)
      cat >"$path" <<'CR'
struct Foo
  def call(*args)
  end
end
CR
      ;;
    proc_call)
      cat >"$path" <<'CR'
struct Proc
  @[Primitive(:proc_call)]
  @[Raises]
  def call(*args : *T) : R
  end
end
CR
      ;;
    *)
      echo "unknown case: $name" >&2
      exit 2
      ;;
  esac
  printf '%s\n' "$path"
}

cases=(bare_def untyped_param typed_param return_annotation splat_param proc_call)
for case_name in "${cases[@]}"; do
  src="$(write_case "$case_name")"
  log="$tmp_dir/$case_name.log"
  out_bin="$tmp_dir/$case_name.bin"

  set +e
  (
    cd "$repo_root"
    scripts/run_safe.sh "$compiler" 20 1024 "$src" --no-prelude --no-codegen -o "$out_bin"
  ) >"$log" 2>&1
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "generated stage2 failed no-codegen semantic def case: $case_name" >&2
    cat "$log" >&2
    exit 1
  fi

  if ! grep -Fq "Parsed 1 top-level expressions" "$log"; then
    echo "generated stage2 did not complete semantic no-codegen check: $case_name" >&2
    cat "$log" >&2
    exit 1
  fi
done

echo "p2_generated_stage2_no_codegen_def_semantic_frontier_ok"
