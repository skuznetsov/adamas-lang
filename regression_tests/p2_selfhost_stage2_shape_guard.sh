#!/usr/bin/env bash
set -euo pipefail

COMPILER="${1:-bin/adamas}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/cv2_p2_selfhost_shapes.XXXXXX)"
OUT_PREFIX="$TMP_DIR/selfhost_shapes"
LOG="$TMP_DIR/selfhost_shapes.log"
MIR="$OUT_PREFIX.mir"

cleanup() {
  if [[ "${KEEP_TMP:-0}" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "[p2_selfhost_stage2_shape_guard] kept tmp: $TMP_DIR" >&2
  fi
}
trap cleanup EXIT

ADAMAS_STOP_AFTER_MIR=1 \
  "$ROOT/scripts/run_safe.sh" "$COMPILER" 300 4096 \
  "$ROOT/src/adamas.cr" --emit mir --no-link -o "$OUT_PREFIX" \
  >"$LOG" 2>&1

if [[ ! -s "$MIR" ]]; then
  echo "p2_selfhost_stage2_shape_guard_failed: missing MIR dump" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

require_pattern() {
  local pattern="$1"
  local label="$2"
  if ! grep -Eq "$pattern" "$MIR"; then
    echo "p2_selfhost_stage2_shape_guard_failed: missing $label" >&2
    exit 1
  fi
}

reject_pattern() {
  local pattern="$1"
  local label="$2"
  if grep -Eq "$pattern" "$MIR"; then
    echo "p2_selfhost_stage2_shape_guard_failed: unexpected $label" >&2
    exit 1
  fi
}

reject_in_function() {
  local func_pattern="$1"
  local bad_pattern="$2"
  local label="$3"
  awk -v fpat="$func_pattern" -v bad="$bad_pattern" -v label="$label" '
    $0 ~ "^func @" && in_func { in_func = 0 }
    $0 ~ fpat { in_func = 1 }
    in_func && $0 ~ bad {
      print "p2_selfhost_stage2_shape_guard_failed: " label ": " $0 > "/dev/stderr"
      exit 42
    }
  ' "$MIR" || {
    status=$?
    [[ "$status" == "42" ]] && exit 1
    exit "$status"
  }
}

require_in_function() {
  local func_pattern="$1"
  local good_pattern="$2"
  local label="$3"
  awk -v fpat="$func_pattern" -v good="$good_pattern" '
    $0 ~ "^func @" && in_func {
      if (!found) exit 42
      in_func = 0
    }
    $0 ~ fpat { in_func = 1 }
    in_func && $0 ~ good { found = 1 }
    END {
      if (in_func && !found) exit 42
    }
  ' "$MIR" || {
    status=$?
    if [[ "$status" == "42" ]]; then
      echo "p2_selfhost_stage2_shape_guard_failed: missing $label" >&2
      exit 1
    fi
    exit "$status"
  }
}

require_array_string_each_index_callback_shape() {
  # The old Array(String)#each_index regression only exists when Array#each is
  # materialized via a nested each_index callback. Some frontiers no longer
  # demand that wrapper, so absence of the nested proc is not a shape failure.
  awk '
    FNR == NR && $0 ~ /^func @Array\(String\)#each\$block/ {
      in_array_each = 1
      next
    }
    FNR == NR && $0 ~ /^func @/ && in_array_each {
      in_array_each = 0
    }
    FNR == NR && in_array_each && $0 ~ /func_pointer @__crystal_block_proc_[0-9]+/ {
      proc = $0
      sub(/^.*func_pointer @/, "", proc)
      sub(/ .*/, "", proc)
      procs[proc] = 1
      next
    }
    FNR == NR { next }
    $0 ~ /^func @__crystal_block_proc_[0-9]+\(/ {
      name = $0
      sub(/^func @/, "", name)
      sub(/\(.*/, "", name)
      if (name in procs) {
        found[name] = 1
        if ($0 !~ /\(%[0-9]+: Int32\)/) {
          print "p2_selfhost_stage2_shape_guard_failed: Array(String)#each_index callback is not Int32-shaped: " $0 > "/dev/stderr"
          exit 42
        }
      }
    }
    END {
      for (proc in procs) {
        if (!(proc in found)) {
          missing = 1
        }
      }
      if (missing) {
        exit 43
      }
    }
  ' "$MIR" "$MIR" || {
    status=$?
    if [[ "$status" == "42" || "$status" == "43" ]]; then
      echo "p2_selfhost_stage2_shape_guard_failed: missing Int32-shaped Array(String)#each_index callback" >&2
      exit 1
    fi
    exit "$status"
  }
}

require_dir_glob_splat_wrapper_shape() {
  # The Dir.glob splat wrapper is also demand-sensitive: later root fixes may
  # avoid materializing it in this self-host MIR. If it is present, keep the old
  # invariant that its forwarding callback is String-shaped.
  awk '
    FNR == NR && $0 ~ /^func @Dir\.glob\$Path \| String_File::MatchOptions_Bool_block_splat/ {
      in_glob = 1
      next
    }
    FNR == NR && $0 ~ /^func @/ && in_glob {
      in_glob = 0
    }
    FNR == NR && in_glob && $0 ~ /func_pointer @__crystal_block_proc_[0-9]+/ {
      proc = $0
      sub(/^.*func_pointer @/, "", proc)
      sub(/ .*/, "", proc)
      procs[proc] = 1
      next
    }
    FNR == NR { next }
    $0 ~ /^func @__crystal_block_proc_[0-9]+\(/ {
      name = $0
      sub(/^func @/, "", name)
      sub(/\(.*/, "", name)
      if (name in procs) {
        found[name] = 1
        if ($0 !~ /\(%[0-9]+: String\)/) {
          print "p2_selfhost_stage2_shape_guard_failed: Dir.glob block_splat forwarding callback is not String-shaped: " $0 > "/dev/stderr"
          exit 42
        }
      }
    }
    END {
      for (proc in procs) {
        if (!(proc in found)) {
          missing = 1
        }
      }
      if (missing) {
        exit 43
      }
    }
  ' "$MIR" "$MIR" || {
    status=$?
    if [[ "$status" == "42" || "$status" == "43" ]]; then
      echo "p2_selfhost_stage2_shape_guard_failed: missing String-shaped Dir.glob block_splat forwarding callback" >&2
      exit 1
    fi
    exit "$status"
  }
}

require_legacy_shape_targets_absent_or_well_typed() {
  require_array_string_each_index_callback_shape
  require_dir_glob_splat_wrapper_shape
}

require_pattern 'global_load @Adamas::Compiler__classvar__CRYSTAL_SRC_PATH : String' \
  'typed CRYSTAL_SRC_PATH global load'

require_legacy_shape_targets_absent_or_well_typed

require_in_function 'func @Adamas::Compiler::Frontend::Parser#is_constant_name\?\$Slice\(UInt8\)' \
  'zext %[0-9]+ : Char' \
  'UInt8-to-Char zext in Parser#is_constant_name?'
reject_in_function 'func @Adamas::Compiler::Frontend::Parser#is_constant_name\?\$Slice\(UInt8\)' \
  'load %[0-9]+ : Char' \
  'stale Slice(UInt8)#[] return repaired to Char load'

reject_in_function 'func @String#byte_index\$Int32_Int32' \
  '^  ret$' \
  'bare return in nilable String#byte_index'

reject_in_function 'func @Dir\.glob\$Path \| String_File::MatchOptions_Bool_block_splat' \
  'call .*_block_splat' \
  'self-recursive Dir.glob block_splat call after tuple rewrap'
reject_in_function 'func @Dir\.glob\$Enumerable_File::MatchOptions_Bool_block' \
  'String#each\$block' \
  'scalar String#each dispatch inside Dir.glob Enumerable block'
reject_pattern '^func @Dir\.glob\$String\(' \
  'scalar Dir.glob$String wrapper after splat default expansion'

require_in_function 'func @Adamas::Compiler::Semantic::TypeInferenceEngine#primitive_metaclass\?\$Adamas::Compiler::Semantic::Type' \
  'bitcast %[0-9]+ : Type#[0-9]+' \
  'PrimitiveType cast before PrimitiveType#name'
reject_in_function 'func @Adamas::Compiler::Semantic::TypeInferenceEngine#primitive_metaclass\?\$Adamas::Compiler::Semantic::Type' \
  'Hash\(String, Hash\(UInt32, Crystal::HIR::Value\)\)#ends_with\?\$String' \
  'stale Hash#ends_with target after PrimitiveType#name'

reject_pattern 'Tuple#includes\?\$String' \
  'generic Tuple#includes?$String target in self-host MIR'
reject_pattern 'T#lookup_macro\$String' \
  'generic T#lookup_macro target in self-host MIR'
reject_pattern 'NameResolver#(current_owner_symbol|in_method_body\?|current_method_is_class_method\?|top_level_scope\?|type_expression_context\?)' \
  'unmaterialized NameResolver zero-arg helper target in self-host MIR'
require_pattern 'func @Adamas::Compiler::Semantic::TypeInferenceEngine#guard_watchdog!' \
  'materialized TypeInferenceEngine guard_watchdog! helper in self-host MIR'
reject_pattern 'Class\.crystal_type_id|Class#crystal_type_id' \
  'Class.crystal_type_id stub target in self-host MIR'
reject_pattern 'Char#ascii_control\?|Char\.ascii_control\?' \
  'Char#ascii_control? stub target in self-host MIR'

echo "p2_selfhost_stage2_shape_guard_ok"
