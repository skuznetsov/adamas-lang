#!/usr/bin/env bash
# Inherited overload lookup preserves source call shape and local priority.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
COMPILER="${1:-}"
ORIGINAL_CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${ORIGINAL_CRYSTAL:-$(command -v crystal || true)}}"
CRYSTAL_STDLIB="${CRYSTAL_PATH:-}"

if [[ -z "$CRYSTAL_STDLIB" ]]; then
  search_dir="$ROOT_DIR"
  for _ in 1 2 3 4 5 6; do
    for candidate in \
      "$search_dir/crystal/src" \
      "$search_dir/Crystal/crystal/src" \
      "$search_dir/Projects/Crystal/crystal/src"; do
      if [[ -d "$candidate" ]]; then
        CRYSTAL_STDLIB="$candidate"
        break 2
      fi
    done
    parent_dir="$(dirname "$search_dir")"
    [[ "$parent_dir" != "$search_dir" ]] || break
    search_dir="$parent_dir"
  done
fi

if [[ -z "$CRYSTAL_STDLIB" && -x "$ORIGINAL_CRYSTAL_BIN" ]]; then
  CRYSTAL_STDLIB="$($ORIGINAL_CRYSTAL_BIN env CRYSTAL_PATH 2>/dev/null || true)"
fi

[[ -x "$COMPILER" && -x "$ORIGINAL_CRYSTAL_BIN" && -x "$SAFE_RUNNER" && -d "$CRYSTAL_STDLIB" ]] || {
  echo "usage: $0 <candidate-compiler>" >&2
  exit 2
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ancestor-call-shape.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf \
    "$WORK_DIR/original.crystal-cache" \
    "$WORK_DIR/permissions.original.crystal-cache" \
    "$WORK_DIR/candidate.crystal-cache" \
    "$WORK_DIR/permissions.candidate.crystal-cache"
  if [[ "$status" -ne 0 || "${KEEP_ARTIFACTS:-0}" == 1 ]]; then
    printf 'kept_artifacts=%s\n' "$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cat >"$WORK_DIR/positive.cr" <<'CRYSTAL'
lib C
  fun putchar(value : Int32) : Int32
end

class Key
end

class Payload
end

class ResultBox(T)
  @value : T

  def initialize(@value : T)
  end

  def first : T
    @value
  end
end

class PairMap(K, V)
  def map(&block : K, V -> T) : ResultBox(T) forall T
    ResultBox(T).new(yield K.new, V.new)
  end
end

class PermissionBase
  def permissions_details(vhost : Key, permission : Payload) : Int32
    42
  end
end

class PermissionInherited < PermissionBase
  def permissions_details : ResultBox(Int32)
    PairMap(Key, Payload).new.map do |vhost, permission|
      permissions_details(vhost: vhost, permission: permission)
    end
  end
end

class PermissionOverride < PermissionBase
  def permissions_details(vhost : Key, permission : Payload) : Int32
    73
  end

  def permissions_details : ResultBox(Int32)
    PairMap(Key, Payload).new.map do |vhost, permission|
      permissions_details(vhost: vhost, permission: permission)
    end
  end
end

class BaseAncestorShape
  def inherited(left : Int32, right : Int32 = 4) : Int32
    left * 10 + right
  end

  def splatted(*values : Int32) : Int32
    31
  end

  def blocked(&block : Int32 -> Int32) : Int32
    yield 5
  end

  def priority(value : Int32) : Int32
    40 + value
  end

  def broad_priority(value : Int32) : Int32
    33
  end
end

class ChildAncestorShape < BaseAncestorShape
  def inherited : Int32
    0
  end

  def inherited_default : Int32
    inherited(left: 2)
  end

  def inherited_named : Int32
    inherited(right: 3, left: 2)
  end

  def splatted : Int32
    0
  end

  def splat_call : Int32
    splatted(*{1, 2})
  end

  def blocked : Int32
    0
  end

  def block_call : Int32
    blocked { |value| value + 7 }
  end

  def priority(value : Int32, extra : Int32 = 1) : Int32
    70 + value + extra
  end

  def priority_call : Int32
    priority(2)
  end

  def broad_priority(value : Object) : Int32
    44
  end

  def broad_priority_call : Int32
    broad_priority(2)
  end
end

# A locally applicable narrow overload must still win over an inherited broad
# overload after local applicability consults the built-in Int32 -> Object chain.
class BroadBaseAncestorShape
  def choose(value : Object) : Int32
    52
  end
end

class NarrowChildAncestorShape < BroadBaseAncestorShape
  def choose(value : Int32) : Int32
    53
  end

  def select_call : Int32
    choose(2)
  end
end

# Reopen the ancestor after the child declares a broad local overload. The
# later, narrower ancestor method must not outrank the local Object method.
class LateBaseAncestorShape
end

class LateChildAncestorShape < LateBaseAncestorShape
  def broad_priority(value : Object) : Int32
    45
  end

  def broad_priority_call : Int32
    broad_priority(2)
  end
end

class LateBaseAncestorShape
  def broad_priority(value : Int32) : Int32
    34
  end
end

def emit(value : Int32)
  C.putchar(48 + value // 10)
  C.putchar(48 + value % 10)
  C.putchar(10)
end

emit(PermissionInherited.new.permissions_details.first)
emit(PermissionOverride.new.permissions_details.first)

shape = ChildAncestorShape.new
emit(shape.inherited_default)
emit(shape.inherited_named)
emit(shape.splat_call)
emit(shape.block_call)
emit(shape.priority_call)
emit(shape.broad_priority_call)
emit(LateChildAncestorShape.new.broad_priority_call)
emit(NarrowChildAncestorShape.new.select_call)
CRYSTAL

cat >"$WORK_DIR/expected" <<'EXPECTED'
42
73
24
23
31
12
73
44
45
53
EXPECTED

status=0
env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/original.crystal-cache" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/original.build.resources" \
  "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 180 8192 build "$WORK_DIR/positive.cr" \
  -o "$WORK_DIR/original.bin" --link-flags=-fuse-ld=/usr/bin/ld \
  >"$WORK_DIR/original.build.log" 2>&1 || status=$?
[[ "$status" == 0 ]] || { cat "$WORK_DIR/original.build.log" >&2; exit 1; }
RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/original.bin" 10 512 \
  >"$WORK_DIR/original.stdout" 2>"$WORK_DIR/original.run.log" || status=$?
[[ "$status" == 0 ]] && grep -Fq '[EXIT: 0]' "$WORK_DIR/original.run.log" || {
  cat "$WORK_DIR/original.run.log" >&2
  exit 1
}
diff -u "$WORK_DIR/expected" "$WORK_DIR/original.stdout"

cat >"$WORK_DIR/permissions_map.cr" <<'CRYSTAL'
alias Permission = NamedTuple(config: String)

class ArityBase
  def permissions_details(vhost : String, permission : Permission)
    {user: "guest", vhost: vhost, config: permission[:config]}
  end
end

class ArityChild < ArityBase
  @permissions : Hash(String, Permission)

  def initialize(@permissions : Hash(String, Permission)); end

  def permissions_details
    @permissions.map { |vhost, permission| permissions_details(vhost, permission) }
  end
end

child = ArityChild.new({"/" => {config: "^$"}})
puts child.permissions_details.first[:user]
CRYSTAL
printf 'guest\n' >"$WORK_DIR/permissions.expected"

status=0
env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/permissions.original.crystal-cache" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/permissions.original.build.resources" \
  "$SAFE_RUNNER" "$ORIGINAL_CRYSTAL_BIN" 300 12288 build "$WORK_DIR/permissions_map.cr" \
  -o "$WORK_DIR/permissions.original.bin" --link-flags=-fuse-ld=/usr/bin/ld \
  >"$WORK_DIR/permissions.original.build.log" 2>&1 || status=$?
[[ "$status" == 0 ]] || { cat "$WORK_DIR/permissions.original.build.log" >&2; exit 1; }
RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/permissions.original.bin" 10 512 \
  >"$WORK_DIR/permissions.original.stdout" 2>"$WORK_DIR/permissions.original.run.log" || status=$?
[[ "$status" == 0 ]] && grep -Fq '[EXIT: 0]' "$WORK_DIR/permissions.original.run.log" || {
  cat "$WORK_DIR/permissions.original.run.log" >&2
  exit 1
}
diff -u "$WORK_DIR/permissions.expected" "$WORK_DIR/permissions.original.stdout"

status=0
env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/candidate.crystal-cache" \
  ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/candidate.build.resources" \
  "$SAFE_RUNNER" "$COMPILER" 180 8192 "$WORK_DIR/positive.cr" --no-debug --no-prelude \
  --no-ast-cache --no-llvm-cache --emit hir -o "$WORK_DIR/candidate.bin" \
  >"$WORK_DIR/candidate.build.log" 2>&1 || status=$?
[[ "$status" == 0 ]] || { cat "$WORK_DIR/candidate.build.log" >&2; exit 1; }
RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/candidate.bin" 10 512 \
  >"$WORK_DIR/candidate.stdout" 2>"$WORK_DIR/candidate.run.log" || status=$?
[[ "$status" == 0 ]] && grep -Fq '[EXIT: 0]' "$WORK_DIR/candidate.run.log" || {
  cat "$WORK_DIR/candidate.run.log" >&2
  exit 1
}
diff -u "$WORK_DIR/expected" "$WORK_DIR/candidate.stdout"
diff -u "$WORK_DIR/original.stdout" "$WORK_DIR/candidate.stdout"

status=0
env CRYSTAL_PATH="$CRYSTAL_STDLIB" CRYSTAL_CACHE_DIR="$WORK_DIR/permissions.candidate.crystal-cache" \
  ADAMAS_LLVM_CACHE=0 ADAMAS_EXTRA_LINK_FLAGS="${ADAMAS_EXTRA_LINK_FLAGS:--fuse-ld=/usr/bin/ld}" \
  RUN_SAFE_RESOURCE_FILE="$WORK_DIR/permissions.candidate.build.resources" \
  "$SAFE_RUNNER" "$COMPILER" 300 12288 "$WORK_DIR/permissions_map.cr" --no-debug \
  --no-ast-cache --no-llvm-cache -o "$WORK_DIR/permissions.candidate.bin" \
  >"$WORK_DIR/permissions.candidate.build.log" 2>&1 || status=$?
[[ "$status" == 0 ]] || { cat "$WORK_DIR/permissions.candidate.build.log" >&2; exit 1; }
RUN_SAFE_PASSTHROUGH_STDIO=1 "$SAFE_RUNNER" "$WORK_DIR/permissions.candidate.bin" 10 512 \
  >"$WORK_DIR/permissions.candidate.stdout" 2>"$WORK_DIR/permissions.candidate.run.log" || status=$?
[[ "$status" == 0 ]] && grep -Fq '[EXIT: 0]' "$WORK_DIR/permissions.candidate.run.log" || {
  cat "$WORK_DIR/permissions.candidate.run.log" >&2
  exit 1
}
diff -u "$WORK_DIR/permissions.expected" "$WORK_DIR/permissions.candidate.stdout"
diff -u "$WORK_DIR/permissions.original.stdout" "$WORK_DIR/permissions.candidate.stdout"
printf 'PASS: ancestor named/default/splat/block calls preserve source shape and local priority\n'
