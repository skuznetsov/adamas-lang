#!/usr/bin/env bash
# Source-oracle coverage for generic class-method aliases and reopened layouts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
ADAMAS_BIN="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-/opt/homebrew/opt/crystal/share/crystal/src}"
COMPILE_TIMEOUT_SEC="${COMPILE_TIMEOUT_SEC:-120}"
COMPILE_MAX_MEM_MB="${COMPILE_MAX_MEM_MB:-4096}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
ORIGINAL_ONLY="${ORIGINAL_ONLY:-0}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generic-reopening-materialization.XXXXXX")"

cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -x "$SAFE_RUNNER" || ! -x "$ORIGINAL_CRYSTAL_BIN" || ! -f "$CRYSTAL_STDLIB/empty.cr" ]]; then
  echo "ERROR: safe runner, original Crystal, or stock Crystal stdlib is unavailable" >&2
  exit 2
fi
if [[ "$ORIGINAL_ONLY" != 1 && ! -x "$ADAMAS_BIN" ]]; then
  echo "ERROR: candidate compiler is unavailable; set ADAMAS_BIN or ORIGINAL_ONLY=1" >&2
  exit 2
fi

ALL_CASES=(bare_class_methods bare_static_independent bare_forall_shadow bare_qualified_formal late_method_publication late_parent_layout source_bound_allocator_layout unbound_owner_signature_negative unbound_owner_body_negative unbound_owner_body_call_negative)
CANDIDATE_FAILURE=0

write_source() {
  local name="$1" path="$WORK_DIR/$name.cr"
  cat >"$path" <<'CRYSTAL'
@[Link("c")]
lib GenericReopeningOutput
  fun putchar(value : Int32) : Int32
end
CRYSTAL

  case "$name" in
    bare_class_methods)
      cat >>"$path" <<'CRYSTAL'
class ReopeningBareBox(T)
  def self.pick(value : Int32) : Int32; 65; end
  def self.pick(value : String) : Int32; 66; end
end

# Materialize two concrete owners before the subsequent reopenings.
ReopeningBareBox(Int32).new
ReopeningBareBox(String).new

class ReopeningBareBox(T)
  def self.pick(value : Bool) : Int32; 67; end
end

class ReopeningBareBox(T)
  def self.pick(value : Int32) : Int32; 68; end
end

GenericReopeningOutput.putchar(ReopeningBareBox.pick(1))
GenericReopeningOutput.putchar(ReopeningBareBox.pick("x"))
GenericReopeningOutput.putchar(ReopeningBareBox.pick(true))
CRYSTAL
      ;;
    bare_static_independent)
      cat >>"$path" <<'CRYSTAL'
class ReopeningBareIndependent(T)
  def self.value : Int32; 65; end
end

GenericReopeningOutput.putchar(ReopeningBareIndependent.value)
CRYSTAL
      ;;
    bare_forall_shadow)
      cat >>"$path" <<'CRYSTAL'
class ReopeningBareForallShadow(T)
  def self.identity(value : T) : T forall T; value; end
end

GenericReopeningOutput.putchar(ReopeningBareForallShadow.identity(65))
CRYSTAL
      ;;
    bare_qualified_formal)
      cat >>"$path" <<'CRYSTAL'
class T
  def code : Int32; 65; end
end

class ReopeningBareQualifiedFormal(T)
  def self.value : ::T; ::T.new; end
end

GenericReopeningOutput.putchar(ReopeningBareQualifiedFormal.value.code)
CRYSTAL
      ;;
    late_method_publication)
      cat >>"$path" <<'CRYSTAL'
class ReopeningLateMethod(T)
  def self.seed : Int32; 1; end
end

# Demand the concrete owner before publishing another source method.
ReopeningLateMethod(Int32).new

class ReopeningLateMethod(T)
  def self.late(value : Int32) : Int32; 65; end
end

GenericReopeningOutput.putchar(ReopeningLateMethod(Int32).late(1))
CRYSTAL
      ;;
    late_parent_layout)
      cat >>"$path" <<'CRYSTAL'
class ReopeningLayoutParent(T)
  @before : Int32 = 65

  def before : Int32; @before; end
end

class ReopeningLayoutChild < ReopeningLayoutParent(Int32)
  @child : Int32 = 67

  def child : Int32; @child; end
end

# Add inherited storage and accessors after the descendant has been declared.
class ReopeningLayoutParent(T)
  @late : T = 66

  def late : T; @late; end
end

child = ReopeningLayoutChild.new
GenericReopeningOutput.putchar(child.before)
GenericReopeningOutput.putchar(child.late)
GenericReopeningOutput.putchar(child.child)
CRYSTAL
      ;;
    source_bound_allocator_layout)
      cat >>"$path" <<'CRYSTAL'
class ReopeningNamedLayout(T)
  @before : Int32 = 0

  def initialize(value : Int32, *, enabled : Bool)
    @before = value
    @enabled = enabled
  end

  def before : Int32; @before; end
  def enabled_code : Int32; @enabled ? 66 : 88; end
end

class ReopeningNamedLayout(T)
  @late : T = 67

  def late : T; @late; end
end

value = ReopeningNamedLayout(Int32).new(value: 65, enabled: true)
GenericReopeningOutput.putchar(value.before)
GenericReopeningOutput.putchar(value.enabled_code)
GenericReopeningOutput.putchar(value.late)
CRYSTAL
      ;;
    unbound_owner_signature_negative)
      cat >>"$path" <<'CRYSTAL'
class ReopeningUnboundOwner(T)
  def self.value : T; 1; end
end

ReopeningUnboundOwner.value
CRYSTAL
      ;;
    unbound_owner_body_negative)
      cat >>"$path" <<'CRYSTAL'
class ReopeningUnboundBodyOwner(T)
  def self.value; T; end
end

ReopeningUnboundBodyOwner.value
CRYSTAL
      ;;
    unbound_owner_body_call_negative)
      cat >>"$path" <<'CRYSTAL'
class ReopeningUnboundBodyCallOwner(T)
  def self.value; T; end
end

ReopeningUnboundBodyCallOwner.value()
CRYSTAL
      ;;
    *)
      printf 'ERROR: unknown case %s\n' "$name" >&2
      return 2
      ;;
  esac
}

compile_one() {
  local stage="$1" name="$2" binary="$WORK_DIR/$stage-$name.bin"
  local log="$WORK_DIR/$stage-$name.build.log" cache="$WORK_DIR/cache-$stage-$name"
  local status=0
  mkdir -p "$cache"
  if [[ "$stage" == original ]]; then
    CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" "$COMPILE_TIMEOUT_SEC" \
      "$COMPILE_MAX_MEM_MB" build --prelude=empty --no-debug "$WORK_DIR/$name.cr" \
      -o "$binary" "--link-flags=$LINK_FLAGS" >"$log" 2>&1 || status=$?
  else
    local -a mode_env=(env -u ADAMAS_EAGER_MONO)
    [[ "$stage" == candidate-eager ]] && mode_env=(env ADAMAS_EAGER_MONO=1)
    CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$cache" \
      ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="$LINK_FLAGS" \
      "${mode_env[@]}" "$SAFE_RUNNER" "$ADAMAS_BIN" "$COMPILE_TIMEOUT_SEC" \
      "$COMPILE_MAX_MEM_MB" "$WORK_DIR/$name.cr" --no-prelude --no-debug \
      --no-ast-cache --no-llvm-cache -o "$binary" >"$log" 2>&1 || status=$?
  fi
  printf '%s\n' "$status" >"$WORK_DIR/$stage-$name.build.status"
  printf '%s\n' "$binary"
}

check_positive() {
  local stage="$1" name="$2" expected="$3" binary status log stdout
  binary="$(compile_one "$stage" "$name")"
  status="$(cat "$WORK_DIR/$stage-$name.build.status")"
  log="$WORK_DIR/$stage-$name.build.log"
  if [[ "$status" != 0 ]] || ! rg -q '^\[EXIT: 0\]( |$)' "$log"; then
    cat "$log" >&2
    printf 'FAIL %s %s: compile did not exit zero\n' "$stage" "$name" >&2
    if [[ "$stage" == original ]]; then return 1; fi
    CANDIDATE_FAILURE=1
    return 0
  fi

  stdout="$WORK_DIR/$stage-$name.stdout"
  log="$WORK_DIR/$stage-$name.run.log"
  status=0
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$binary" 5 512 >"$stdout" 2>"$log" || status=$?
  if [[ "$status" != 0 ]] || ! rg -q '^\[EXIT: 0\]( |$)' "$log"; then
    cat "$log" "$stdout" >&2
    printf 'FAIL %s %s: native run did not exit zero\n' "$stage" "$name" >&2
    if [[ "$stage" == original ]]; then return 1; fi
    CANDIDATE_FAILURE=1
    return 0
  fi
  printf '%s' "$expected" >"$WORK_DIR/$name.expected"
  if ! diff -u "$WORK_DIR/$name.expected" "$stdout"; then
    printf 'FAIL %s %s: stdout differed from expected bytes\n' "$stage" "$name" >&2
    if [[ "$stage" == original ]]; then return 1; fi
    CANDIDATE_FAILURE=1
    return 0
  fi
  if [[ "$stage" != original ]] && ! diff -u "$WORK_DIR/original-$name.stdout" "$stdout"; then
    printf 'FAIL %s %s: stdout differed from original Crystal\n' "$stage" "$name" >&2
      CANDIDATE_FAILURE=1
      return 0
  fi
  printf 'PASS %s %s output=%q\n' "$stage" "$name" "$expected"
}

check_unbound_rejected() {
  local stage="$1" name="$2" binary status log
  binary="$(compile_one "$stage" "$name")"
  status="$(cat "$WORK_DIR/$stage-$name.build.status")"
  log="$WORK_DIR/$stage-$name.build.log"
  if [[ "$status" == 0 ]] && rg -q '^\[EXIT: 0\]( |$)' "$log"; then
    printf 'FAIL %s %s: candidate accepted source rejected by stock Crystal\n' "$stage" "$name" >&2
    CANDIDATE_FAILURE=1
    return 0
  fi
  if [[ "$status" != 1 ]] || ! rg -q '^\[EXIT: 1\]( |$)' "$log" || ! rg -qi \
    "can't infer the type parameter|generic type arguments must be specified|generic class.*without specifying" "$log"; then
    cat "$log" >&2
    printf 'FAIL %s %s: expected a generic-type inference rejection\n' "$stage" "$name" >&2
    if [[ "$stage" == original ]]; then return 1; fi
    CANDIDATE_FAILURE=1
    return 0
  fi
  if rg -qi 'syntax error|parser errors|internal compiler error|unhandled exception|timed out|resource limit' "$log"; then
    cat "$log" >&2
    printf 'FAIL %s %s: rejection was not a source-level type error\n' "$stage" "$name" >&2
    if [[ "$stage" == original ]]; then return 1; fi
    CANDIDATE_FAILURE=1
    return 0
  fi
  printf 'PASS %s %s rejected an unbound generic owner\n' "$stage" "$name"
}

for name in "${ALL_CASES[@]}"; do
  write_source "$name"
  if [[ "$name" == unbound_owner_signature_negative || "$name" == unbound_owner_body_negative || "$name" == unbound_owner_body_call_negative ]]; then
    check_unbound_rejected original "$name"
    if [[ "$ORIGINAL_ONLY" != 1 ]]; then
      check_unbound_rejected candidate-lazy "$name"
      check_unbound_rejected candidate-eager "$name"
    fi
  else
    case "$name" in
      bare_class_methods) expected=DBC ;;
      bare_static_independent|bare_forall_shadow|bare_qualified_formal) expected=A ;;
      late_method_publication) expected=A ;;
      late_parent_layout) expected=ABC ;;
      source_bound_allocator_layout) expected=ABC ;;
    esac
    check_positive original "$name" "$expected"
    if [[ "$ORIGINAL_ONLY" != 1 ]]; then
      check_positive candidate-lazy "$name" "$expected"
      check_positive candidate-eager "$name" "$expected"
    fi
  fi
done

if [[ "$CANDIDATE_FAILURE" != 0 ]]; then
  echo "FAIL: candidate had one or more source-contract mismatches" >&2
  exit 1
fi
