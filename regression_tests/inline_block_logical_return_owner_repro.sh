#!/usr/bin/env bash
# Inline-yield blocks must route `return` to their lexical method, not the
# physical HIR function that happens to host several inlined methods.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE="$ROOT_DIR/scripts/run_safe.sh"
CANDIDATE="${ADAMAS_BIN:-${1:-$ROOT_DIR/bin/adamas}}"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/inline-block-logical-return-owner.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK" >&2
  else
    rm -rf -- "$WORK"
  fi
}
trap cleanup EXIT

cat > "$WORK/valid_returns.cr" <<'CRYSTAL'
@[Link("c")]
lib InlineReturnOwnerNative
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
end

def owner_sync(&)
  yield
end

def nil_step(flag : Bool, &) : Nil
  owner_sync do
    return unless flag
    yield 65
  end
end

def nil_probe(flag : Bool, &) : Bool
  nil_step(flag) do |entry|
    yield entry
    return true
  end
  false
end

def forwarded_probe(flag : Bool, &) : Bool
  owner_sync do
    nil_step(flag) do |entry|
      yield entry
      return true
    end
  end
  false
end

def no_return_inner(flag : Bool, &)
  owner_sync { yield flag }
end

def no_return_probe(flag : Bool) : Bool
  no_return_inner(flag) do |entry|
    owner_sync { entry }
  end
end

def scalar_step(flag : Bool, &) : Int32
  owner_sync do
    return 73 unless flag
    yield 65
  end
  74
end

def scalar_probe(flag : Bool, &) : Int32
  scalar_step(flag) do |entry|
    yield entry
    return 81
  end
  67
end

def physical_return_step(&)
  owner_sync { yield }
end

def physical_return_probe : Bool
  physical_return_step { return true }
  false
end

def generic_step(value : T, &) : Int32 forall T
  owner_sync { return 75 }
  76
end

def boolean_after_generic_integer : Bool
  generic_step(75) {}
  true
end

def boolean_after_generic_boolean : Bool
  generic_step(true) {}
  true
end

if nil_probe(InlineReturnOwnerNative.getpid > 0) { |entry| entry == 65 }
  InlineReturnOwnerNative.putchar(65)
else
  InlineReturnOwnerNative.putchar(88)
end
if nil_probe(InlineReturnOwnerNative.getpid < 0) { |entry| entry == 65 }
  InlineReturnOwnerNative.putchar(88)
else
  InlineReturnOwnerNative.putchar(68)
end
if physical_return_probe
  InlineReturnOwnerNative.putchar(80)
else
  InlineReturnOwnerNative.putchar(88)
end
if forwarded_probe(InlineReturnOwnerNative.getpid > 0) { |entry| entry == 65 }
  InlineReturnOwnerNative.putchar(78)
else
  InlineReturnOwnerNative.putchar(88)
end
if no_return_probe(InlineReturnOwnerNative.getpid > 0)
  InlineReturnOwnerNative.putchar(81)
else
  InlineReturnOwnerNative.putchar(88)
end
if boolean_after_generic_integer
  InlineReturnOwnerNative.putchar(71)
else
  InlineReturnOwnerNative.putchar(88)
end
if boolean_after_generic_boolean
  InlineReturnOwnerNative.putchar(72)
else
  InlineReturnOwnerNative.putchar(88)
end
scalar_result = scalar_probe(InlineReturnOwnerNative.getpid < 0) { |entry| entry == 65 }
if scalar_result == 67
  InlineReturnOwnerNative.putchar(67)
elsif scalar_result == 73
  InlineReturnOwnerNative.putchar(73)
else
  InlineReturnOwnerNative.putchar(88)
end
if scalar_probe(InlineReturnOwnerNative.getpid > 0) { |entry| entry == 65 } == 81
  InlineReturnOwnerNative.putchar(81)
else
  InlineReturnOwnerNative.putchar(88)
end
CRYSTAL

# A captured callback gets its own HIR function. Inlined methods inside
# that function must own their early returns just as in an ordinary method.
cat > "$WORK/proc_inline_returns.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

class Context
  @status : Int32

  def initialize(@status : Int32)
  end

  def status : Int32
    @status
  end
end

class Router
  alias Action = Proc(Context, Bool, Context)

  def post(context : Context, allowed : Bool, &action : Action) : Context
    action.call(context, allowed)
  end

  def with_vhost(context, allowed, *, marker = 65, &)
    if allowed
      yield marker
    else
      access_refused
    end
    context
  end

  private def access_refused
    LibC.exit(9)
  end

  private def maybe_emit(enabled, &)
    return unless enabled
    yield
  end

  def register_routes(enabled : Bool) : Context
    post(Context.new(7), true) do |context, allowed|
      with_vhost(context, allowed) do |marker|
        maybe_emit(enabled) { LibC.putchar(76) }
        LibC.putchar(marker)
        nil
      end
    end
  end
end

router = Router.new
LibC.exit(1) unless router.register_routes(false).status == 7
LibC.exit(2) unless router.register_routes(true).status == 7
CRYSTAL

# Resolving render's inferred result while lowering the callback enters a
# separate function. Its inlined gate must not return from the callback.
cat > "$WORK/reentrant_inline_returns.cr" <<'CRYSTAL'
lib LibC
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
end

def gate(enabled : Bool, &)
  return unless enabled
  yield
end

class Context
  def write : Int32
    LibC.putchar(67)
  end
end

class Handler
  def render(context, flag : Bool)
    gate(flag) { LibC.putchar(65) }
    context
  end

  def on(& : Context -> Context)
    yield Context.new
  end

  def run(flag : Bool)
    on do |context|
      render(context, flag)
    end.write
  end
end

handler = Handler.new
handler.run(LibC.getpid < 0)
handler.run(LibC.getpid > 0)
CRYSTAL

cases=(valid_returns proc_inline_returns reentrant_inline_returns)
expected_stdout=('ADPNQGHCQ' 'ALA' 'CAC')

run_case() {
  local mode="$1" index="$2" probe="${cases[$2]}" status
  "${compile[@]}" "$WORK/$probe.cr" -o "$WORK/$mode.$probe" > "$WORK/$mode.$probe.compile.log" 2>&1 || {
    cat "$WORK/$mode.$probe.compile.log" >&2
    return 1
  }
  RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE" "$WORK/$mode.$probe" 5 512 \
    > "$WORK/$mode.$probe.stdout" 2> "$WORK/$mode.$probe.run.log" || {
    cat "$WORK/$mode.$probe.run.log" >&2
    return 1
  }
  printf '%s' "${expected_stdout[$index]}" > "$WORK/$probe.expected.stdout"
  diff -u "$WORK/$probe.expected.stdout" "$WORK/$mode.$probe.stdout" || return 1
  printf 'PASS: %s %s\n' "$mode" "$probe"
}

modes=(stock lazy eager)
[[ "${ORIGINAL_ONLY:-0}" == 1 ]] && modes=(stock)
[[ "${CANDIDATE_ONLY:-0}" == 1 ]] && modes=(lazy eager)
failed=0
for mode in "${modes[@]}"; do
  if [[ "$mode" == stock ]]; then
    compile=(env CRYSTAL_CACHE_DIR="$WORK/cache.stock" "$SAFE" "$ORIGINAL" 120 4096 build
      --prelude=empty --single-module --no-debug --link-flags="$LINK_FLAGS")
  else
    mode_env=(env -u ADAMAS_EAGER_HIR -u ADAMAS_EAGER_MONO)
    [[ "$mode" == eager ]] && mode_env=(env -u ADAMAS_EAGER_HIR ADAMAS_EAGER_MONO=1)
    compile=("${mode_env[@]}" ADAMAS_LLVM_CACHE=0 "$SAFE" "$CANDIDATE" 120 4096
      --no-prelude --no-debug --no-ast-cache --no-llvm-cache)
  fi
  for index in "${!cases[@]}"; do
    probe="${cases[$index]}"
    if [[ -n "${ONLY_CASES:-}" && ",${ONLY_CASES}," != *",${probe},"* ]]; then
      continue
    fi
    if ! run_case "$mode" "$index"; then
      printf 'FAIL: %s %s\n' "$mode" "$probe" >&2
      failed=1
      [[ "${CONTINUE_ON_FAILURE:-0}" == 1 ]] || exit 1
    fi
  done
done
exit "$failed"
