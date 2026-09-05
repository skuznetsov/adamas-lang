#!/usr/bin/env bash
# A macro-expanded class constructor must keep its receiverless call shape.
# Full prelude is intentional: the expansion shares the original stdlib arena.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/macro_receiver_scope.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == 1 ]]; then
    echo "kept_tmp=$WORKDIR"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT
cat >"$WORKDIR/repro.cr" <<'CR'
class DescriptorMaker
  def build(fd : Int32)
    IO::FileDescriptor.new(fd)
  end
end
fd = LibC.open("/dev/null", LibC::O_RDONLY)
LibC.exit(80) if fd < 0
io = DescriptorMaker.new.build(fd)
LibC.exit(81) unless io.fd == fd
LibC.close(fd)
LibC.exit(0)
CR

for mode in original adamas; do
  if [[ "$mode" == original ]]; then
    build=("${ORIGINAL_CRYSTAL:-crystal}" 120 8192 build "$WORKDIR/repro.cr")
  else
    build=("$COMPILER" 120 8192 "$WORKDIR/repro.cr")
  fi
  if ! CRYSTAL_CACHE_DIR="$WORKDIR/cache" "$ROOT_DIR/scripts/run_safe.sh" \
    "${build[@]}" -o "$WORKDIR/$mode.bin" >"$WORKDIR/$mode.compile.log" 2>&1; then
    echo "FAIL: $mode macro receiver provenance compilation" >&2
    tail -35 "$WORKDIR/$mode.compile.log" >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/run_safe.sh" "$WORKDIR/$mode.bin" 5 512 \
    >"$WORKDIR/$mode.run.log" 2>&1; then
    echo "FAIL: $mode macro receiver provenance runtime" >&2
    cat "$WORKDIR/$mode.run.log" >&2
    exit 1
  fi
done
echo "PASS: expanded class constructor preserves the supplied file descriptor"
