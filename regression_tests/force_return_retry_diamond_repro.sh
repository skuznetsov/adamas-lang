#!/usr/bin/env bash
# A provisional generic factory result must settle independently of DAG order.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
STDLIB="${CRYSTAL_PATH:-}"
if [[ -z "$STDLIB" && -x "$ORIGINAL" ]]; then
  STDLIB="$("$ORIGINAL" env CRYSTAL_PATH)"
fi
original_link=()
if [[ "$(uname -s)" == Darwin ]]; then
  original_link=(--link-flags=-fuse-ld=/usr/bin/ld)
  export ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/force-return-retry-diamond.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf -- "$WORK"/cache.*
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

if [[ ! -x "$SAFE" || ! -x "$ORIGINAL" || -z "$STDLIB" ]]; then
  echo 'ERROR: safe runner, stock Crystal, and its standard library path are required' >&2
  exit 2
fi
if [[ "${ORIGINAL_ONLY:-0}" != 1 && ! -x "$CANDIDATE" ]]; then
  echo 'ERROR: candidate compiler is unavailable' >&2
  exit 2
fi

cat > "$WORK/output.cr" <<'CRYSTAL'
@[Link("c")]
lib RetryDiamondNative
  fun putchar(value : Int32) : Int32
end
CRYSTAL

write_diamond() {
  local probe="$1" leaf='RetryDiamondPayload.new'
  [[ "$probe" == wrong_leaf ]] && leaf=true
  cat "$WORK/output.cr" > "$WORK/$probe.cr"
  cat >> "$WORK/$probe.cr" <<'CRYSTAL'
class RetryDiamondPayload
  def marker : Int32
    65
  end
end
class RetryDiamondD
  def self.new(value : T) forall T
CRYSTAL
  printf '    %s\n' "$leaf" >> "$WORK/$probe.cr"
  cat >> "$WORK/$probe.cr" <<'CRYSTAL'
  end
end
class RetryDiamondE
  def self.new(value : T) forall T
    RetryDiamondPayload.new
  end
end
class RetryDiamondB
  def self.new(value : T) forall T
    RetryDiamondD.new(value)
  end
end
class RetryDiamondC
  def self.new(value : T) forall T
    result = RetryDiamondB.new(value)
    RetryDiamondE.new(value)
    result
  end
end
class RetryDiamondA
  def self.new(value : T) forall T
CRYSTAL
  if [[ "$probe" == order_control ]]; then
    cat >> "$WORK/$probe.cr" <<'CRYSTAL'
    result = RetryDiamondC.new(value)
    RetryDiamondB.new(value)
    result
CRYSTAL
  else
    cat >> "$WORK/$probe.cr" <<'CRYSTAL'
    RetryDiamondB.new(value)
    RetryDiamondC.new(value)
CRYSTAL
  fi
  cat >> "$WORK/$probe.cr" <<'CRYSTAL'
  end
end
class RetryDiamondOuter0
  def self.new(value : T) forall T
    RetryDiamondA.new(value)
  end
end
class RetryDiamondOuter1
  def self.new(value : T) forall T
    RetryDiamondOuter0.new(value)
  end
end
class RetryDiamondOuter2
  def self.new(value : T) forall T
    RetryDiamondOuter1.new(value)
  end
end
def retry_diamond_observe(value : RetryDiamondPayload) : Int32
  value.marker
end
RetryDiamondNative.putchar(retry_diamond_observe(RetryDiamondOuter2.new(1)))
CRYSTAL
}

for probe in diamond order_control wrong_leaf; do
  write_diamond "$probe"
done
cat "$WORK/output.cr" > "$WORK/recursive_control.cr"
cat >> "$WORK/recursive_control.cr" <<'CRYSTAL'
class RetryCycleA
  def self.new(value : T) : Int32 forall T
    return 65 if value == 0
    RetryCycleB.new(value &- 1)
  end
end
class RetryCycleB
  def self.new(value : T) : Int32 forall T
    RetryCycleA.new(value)
  end
end
def retry_cycle_observe(value : Int32) : Int32
  value
end
RetryDiamondNative.putchar(retry_cycle_observe(RetryCycleA.new(2)))
CRYSTAL

cases=(diamond order_control wrong_leaf recursive_control)
if [[ -n "${ONLY_CASES:-}" ]]; then
  for selected in ${ONLY_CASES//,/ }; do
    known=0
    for probe in "${cases[@]}"; do
      [[ "$selected" == "$probe" ]] && known=1
    done
    if [[ "$known" != 1 ]]; then
      printf 'ERROR: unknown case: %s\n' "$selected" >&2
      exit 2
    fi
  done
fi

run_case() {
  local mode="$1" probe="$2" status
  if [[ "$probe" == wrong_leaf ]]; then
    set +e
    "${compile[@]}" "$WORK/$probe.cr" -o "$WORK/$mode.$probe" > "$WORK/$mode.$probe.compile.log" 2>&1
    status=$?
    set -e
    if [[ "$status" != 1 ]] ||
       ! grep -Eq 'retry_diamond_observe.*Bool|must be RetryDiamondPayload, not Bool' "$WORK/$mode.$probe.compile.log"; then
      cat "$WORK/$mode.$probe.compile.log" >&2
      printf 'FAIL: %s %s expected the genuine result mismatch (compile1), got%s\n' "$mode" "$probe" "$status" >&2
      return 1
    fi
  else
    "${compile[@]}" "$WORK/$probe.cr" -o "$WORK/$mode.$probe" > "$WORK/$mode.$probe.compile.log" 2>&1 || {
      cat "$WORK/$mode.$probe.compile.log" >&2
      return 1
    }
    RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/$mode.$probe" 5 512 \
      > "$WORK/$mode.$probe.stdout" 2> "$WORK/$mode.$probe.run.log" || {
      cat "$WORK/$mode.$probe.run.log" >&2
      return 1
    }
    printf A > "$WORK/$probe.expected.stdout"
    diff -u "$WORK/$probe.expected.stdout" "$WORK/$mode.$probe.stdout" || return 1
  fi
  printf 'PASS: %s %s\n' "$mode" "$probe"
}

modes=(stock lazy eager)
[[ "${ORIGINAL_ONLY:-0}" == 1 ]] && modes=(stock)
[[ "${CANDIDATE_ONLY:-0}" == 1 ]] && modes=(lazy eager)
failed=0
for mode in "${modes[@]}"; do
  if [[ "$mode" == stock ]]; then
    compile=(env CRYSTAL_PATH="$STDLIB" CRYSTAL_CACHE_DIR="$WORK/cache.stock" "$SAFE" "$ORIGINAL" 120 4096 build
      --prelude=empty --no-debug "${original_link[@]}")
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    [[ "$mode" == eager ]] && mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    compile=("${mode_env[@]}" CRYSTAL_PATH="$STDLIB" ADAMAS_LLVM_CACHE=0 "$SAFE" "$CANDIDATE" 120 4096
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi
  for probe in "${cases[@]}"; do
    [[ -n "${ONLY_CASES:-}" && ",${ONLY_CASES}," != *",${probe},"* ]] && continue
    if ! run_case "$mode" "$probe"; then
      printf 'FAIL: %s %s\n' "$mode" "$probe" >&2
      failed=1
      [[ "${CONTINUE_ON_FAILURE:-0}" == 1 ]] || exit 1
    fi
  done
done
exit "$failed"
