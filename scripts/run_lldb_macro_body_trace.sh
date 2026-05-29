#!/usr/bin/env bash
# Run adamas under LLDB with scripts/lldb_macro_body_trace.py (macro body completion trace).
#
# Usage:
#   scripts/run_lldb_macro_body_trace.sh /path/to/adamas scripts/macro_dump_stdlib_heavy_carrier.cr
#
# Filter repeated producers (examples — match JSONL oracle keys):
#   CRYSTAL_V2_LLDB_MB_FILTER_PATH_SUBSTR=byte_format.cr \
#   CRYSTAL_V2_LLDB_MB_FILTER_PIECES=35 \
#   CRYSTAL_V2_LLDB_MB_MAX_STOPS=8 \
#   scripts/run_lldb_macro_body_trace.sh bin/adamas scripts/macro_dump_stdlib_heavy_carrier.cr
#
# object.cr L609-616 / pieces=7:
#   CRYSTAL_V2_LLDB_MB_FILTER_PATH_SUBSTR=object.cr \
#   CRYSTAL_V2_LLDB_MB_FILTER_PIECES=7 \
#   CRYSTAL_V2_LLDB_MB_FILTER_START_LINE=609 \
#   CRYSTAL_V2_LLDB_MB_FILTER_END_LINE=616 \
#   ...
#
# tuple.cr L367-369 / pieces=3 (high call_count):
#   CRYSTAL_V2_LLDB_MB_FILTER_PATH_SUBSTR=tuple.cr \
#   CRYSTAL_V2_LLDB_MB_FILTER_PIECES=3 \
#   CRYSTAL_V2_LLDB_MB_FILTER_START_LINE=367 \
#   CRYSTAL_V2_LLDB_MB_FILTER_END_LINE=369 \
#   ...
#
# primitives.cr L428-581 / pieces=113 (giant single expansion — expect 1 hit):
#   CRYSTAL_V2_LLDB_MB_FILTER_PATH_SUBSTR=primitives.cr \
#   CRYSTAL_V2_LLDB_MB_FILTER_PIECES=113 \
#   CRYSTAL_V2_LLDB_MB_FILTER_START_LINE=428 \
#   CRYSTAL_V2_LLDB_MB_FILTER_END_LINE=581 \
#   ...
#
# Immediate giant diagnostic (stderr JSON, no lldb): CRYSTAL_V2_MACRO_BODY_GIANT_DIAG=1
# (see macro_expander.cr / maybe_record_macro_body_output).
#
# Requires: adamas built with --debug (same as lldb_smoke / local DWARF work).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${1:?path to adamas binary}"
CARRIER="${2:?path to carrier .cr}"
OUT="${3:-/tmp/adamas_lldb_macro_carrier_out}"

export CRYSTAL_V2_MACRO_BODY_OUTPUT_STATS_DUMP="${CRYSTAL_V2_MACRO_BODY_OUTPUT_STATS_DUMP:-1}"

CARRIER_ABS="$CARRIER"
[[ "$CARRIER_ABS" = /* ]] || CARRIER_ABS="$REPO_ROOT/$CARRIER"

lldb --batch \
  -o "target create \"$COMPILER\"" \
  -o "settings set -- target.run-args \"$CARRIER_ABS\" -o \"$OUT\"" \
  -o "command script import \"$REPO_ROOT/scripts/lldb_macro_body_trace.py\"" \
  -o "macro-body-trace-setup" \
  -o "run" \
  -o "quit"

rm -f "$OUT"
