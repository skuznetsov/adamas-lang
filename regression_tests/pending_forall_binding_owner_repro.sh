#!/usr/bin/env bash
# A deferred owner snapshot must preserve the selected method's forall binding.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pending-forall-binding-owner.XXXXXX")"
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

if [[ ! -x "$SAFE" || ! -x "$ORIGINAL" || ! -f "$STDLIB/empty.cr" ]]; then
  echo 'ERROR: safe runner, stock Crystal, and stock empty prelude are required' >&2
  exit 2
fi
if [[ "${ORIGINAL_ONLY:-0}" != 1 && ! -x "$CANDIDATE" ]]; then
  echo 'ERROR: candidate compiler is unavailable' >&2
  exit 2
fi
if [[ "${ORIGINAL_ONLY:-0}" == 1 && "${CANDIDATE_ONLY:-0}" == 1 ]]; then
  echo 'ERROR: ORIGINAL_ONLY and CANDIDATE_ONLY are mutually exclusive' >&2
  exit 2
fi

write_declaration() {
  local formal="$1" destination="$2"
  cat > "$destination" <<CRYSTAL
@[Link("c")]
lib PendingForallOutput
  fun putchar(value : Int32) : Int32
end
module LLVM
  enum AtomicOrdering
    SequentiallyConsistent = 7
  end
end
struct Atomic(T)
  module Ops
    @[Primitive(:cmpxchg)]
    def self.cmpxchg(ptr : $formal*, cmp : $formal, new : $formal, success_ordering : LLVM::AtomicOrdering, failure_ordering : LLVM::AtomicOrdering) : {$formal, Bool} forall $formal
    end
  end
end
def pending_int8_only(value : Int8) : Int32
  65
end
def pending_bool_only(value : Bool) : Int32
  66
end
CRYSTAL
}

write_declaration T "$WORK/namespace_collision.cr"
cat >> "$WORK/namespace_collision.cr" <<'CRYSTAL'
struct Atomic(T)
  def self.run(value : Int8)
    Atomic::Ops.cmpxchg(pointerof(value), value, value, LLVM::AtomicOrdering::SequentiallyConsistent, LLVM::AtomicOrdering::SequentiallyConsistent)
  end
end
result = Atomic(Bool).run(65_i8)
PendingForallOutput.putchar(pending_int8_only(result[0])) if result[1]
CRYSTAL

write_declaration T "$WORK/renamed_outer.cr"
cat >> "$WORK/renamed_outer.cr" <<'CRYSTAL'
struct PendingForallRenamed(T)
  def self.run(value : Int8)
    Atomic::Ops.cmpxchg(pointerof(value), value, value, LLVM::AtomicOrdering::SequentiallyConsistent, LLVM::AtomicOrdering::SequentiallyConsistent)
  end
end
result = PendingForallRenamed(Bool).run(65_i8)
PendingForallOutput.putchar(pending_int8_only(result[0])) if result[1]
CRYSTAL

write_declaration U "$WORK/distinct_callee_formal.cr"
cat >> "$WORK/distinct_callee_formal.cr" <<'CRYSTAL'
struct Atomic(T)
  def self.run(value : Int8)
    Atomic::Ops.cmpxchg(pointerof(value), value, value, LLVM::AtomicOrdering::SequentiallyConsistent, LLVM::AtomicOrdering::SequentiallyConsistent)
  end
end
result = Atomic(Bool).run(65_i8)
PendingForallOutput.putchar(pending_int8_only(result[0])) if result[1]
CRYSTAL

write_declaration T "$WORK/owner_binding.cr"
cat >> "$WORK/owner_binding.cr" <<'CRYSTAL'
struct Atomic(T)
  def self.identity(value : T) : T
    value
  end
  def self.run(value : T)
    identity(value)
  end
end
PendingForallOutput.putchar(pending_bool_only(Atomic(Bool).run(false)))
CRYSTAL

cat > "$WORK/partial_shadow.cr" <<'CRYSTAL'
@[Link("c")]
lib PendingForallOutput
  fun putchar(value : Int32) : Int32
end
struct Atomic(T, U)
  def self.pair(owner : T, value : U) : {T, U} forall U
    {owner, value}
  end
  def self.run(owner : T, value : Int8)
    result = pair(owner, value)
    PendingForallOutput.putchar(pending_bool_only(result[0]))
    PendingForallOutput.putchar(pending_int8_only(result[1]))
  end
end
def pending_int8_only(value : Int8) : Int32
  65
end
def pending_bool_only(value : Bool) : Int32
  66
end
Atomic(Bool, Bool).run(false, 65_i8)
CRYSTAL

# A selected method formal also shadows a same-named lexical alias. Keep
# both alias locations: contextual fallback treated the namespace differently.
awk '/^struct Atomic\(T, U\)/ { print "alias U = String" } { print }' \
  "$WORK/partial_shadow.cr" > "$WORK/partial_shadow_root_alias.cr"
awk '
  /^struct Atomic\(T, U\)/ {
    print "module ParameterAliasNamespace"
    print "  alias U = String"
  }
  /^def pending_int8_only/ { print "end" }
  /^Atomic\(Bool, Bool\)/ { sub(/^Atomic/, "ParameterAliasNamespace::Atomic") }
  { print }
' "$WORK/partial_shadow.cr" > "$WORK/partial_shadow_namespace_alias.cr"

cat > "$WORK/module_bound_alias.cr" <<'CRYSTAL'
@[Link("c")]
lib PendingForallOutput
  fun putchar(value : Int32) : Int32
end
module ModuleParameterAlias
  alias U = String
  def self.identity(value : U) : U forall U
    value
  end
end
def pending_int8_only(value : Int8) : Int32
  65
end
PendingForallOutput.putchar(pending_int8_only(ModuleParameterAlias.identity(65_i8)))
CRYSTAL

cat > "$WORK/global_bound_alias.cr" <<'CRYSTAL'
@[Link("c")]
lib PendingForallOutput
  fun putchar(value : Int32) : Int32
end
alias U = String
def global_parameter_identity(value : U) : U forall U
  value
end
def pending_int8_only(value : Int8) : Int32
  65
end
PendingForallOutput.putchar(pending_int8_only(global_parameter_identity(65_i8)))
CRYSTAL

sed 's/pending_int8_only(result\[0\])/pending_bool_only(result[0])/' \
  "$WORK/namespace_collision.cr" > "$WORK/wrong_result.cr"
sed 's/pointerof(value), value, value,/pointerof(value), true, true,/' \
  "$WORK/namespace_collision.cr" > "$WORK/wrong_argument.cr"

cases=(namespace_collision renamed_outer distinct_callee_formal owner_binding partial_shadow partial_shadow_root_alias partial_shadow_namespace_alias module_bound_alias global_bound_alias wrong_result wrong_argument)
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
  local mode="$1" probe="$2" status=0
  local output="$WORK/$mode.$probe"
  "${compile[@]}" "$WORK/$probe.cr" -o "$output" > "$output.compile.log" 2>&1 || status=$?
  if [[ "$probe" == wrong_result || "$probe" == wrong_argument ]]; then
    local target
    if [[ "$probe" == wrong_result ]]; then
      target=pending_bool_only
    else
      target=cmpxchg
    fi
    if [[ "$status" != 1 ]] || ! grep -Fq "$target" "$output.compile.log" ||
       ! grep -q Int8 "$output.compile.log" || ! grep -q Bool "$output.compile.log" ||
       ! grep -Eq 'no overload matches|expected|must be' "$output.compile.log"; then
      cat "$output.compile.log" >&2
      printf 'FAIL: %s %s expected a source argument rejection (compile1), got%s\n' "$mode" "$probe" "$status" >&2
      return 1
    fi
  elif [[ "$status" != 0 ]]; then
    cat "$output.compile.log" >&2
    return 1
  else
    env RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$output" 5 512 > "$output.stdout" 2> "$output.run.log" || {
      cat "$output.run.log" >&2
      return 1
    }
    if [[ "$probe" == partial_shadow* ]]; then
      printf BA > "$WORK/$probe.expected.stdout"
    elif [[ "$probe" == owner_binding ]]; then
      printf B > "$WORK/$probe.expected.stdout"
    else
      printf A > "$WORK/$probe.expected.stdout"
    fi
    diff -u "$WORK/$probe.expected.stdout" "$output.stdout" || return 1
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
      --prelude=empty --no-debug --link-flags="$LINK_FLAGS")
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    [[ "$mode" == eager ]] && mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    compile=("${mode_env[@]}" CRYSTAL_PATH="$STDLIB" ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS"
      "$SAFE" "$CANDIDATE" 120 4096 --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
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
