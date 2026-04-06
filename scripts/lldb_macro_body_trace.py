# LLDB Python script: trace macro body completions at MacroBodyOutputStatsDump.record
# (macro_expander.cr:1402 — inside maybe_record_macro_body_output).
#
# Why line 1402 (not evaluate_macro_body / line 1512): DWARF exposes a correct
# `span` (start_line/end_line), `pieces_count`, `output.bytesize`, and `body_node`
# here. `body_id` (ExprId) arguments are currently mis-described in debug info and
# should not be trusted in LLDB; use `body_node` pointer identity instead.
#
# Usage (from repo root, after building crystal_v2 with --debug):
#
#   export CRYSTAL_V2_MACRO_BODY_OUTPUT_STATS_DUMP=1   # optional; same compile as oracle
#   export CRYSTAL_V2_LLDB_MB_FILTER_PATH_SUBSTR=byte_format.cr
#   export CRYSTAL_V2_LLDB_MB_FILTER_PIECES=35
#   # Optional exact span match (from JSONL span_start_line / span_end_line):
#   # export CRYSTAL_V2_LLDB_MB_FILTER_START_LINE=123
#   # export CRYSTAL_V2_LLDB_MB_FILTER_END_LINE=165
#   export CRYSTAL_V2_LLDB_MB_MAX_STOPS=50
#   export CRYSTAL_V2_LLDB_MB_BT_DEPTH=12
#
#   lldb -b -o 'command script import scripts/lldb_macro_body_trace.py' \
#        -o 'macro-body-trace-setup' \
#        -o 'run' \
#        -o 'quit' \
#        -- bin/crystal_v2 -- scripts/macro_dump_stdlib_heavy_carrier.cr -o /tmp/out
#
# Or set target + run-args first, then `macro-body-trace-setup`, then `run`.
#
# Environment is read when the breakpoint is hit; export vars in the shell before
# launching lldb so os.environ in this module sees them.
#
# Follow-ups (manual in lldb): `image lookup -r -n to_macro_output` and breakpoints on
# builder.cr write / increase_capacity_by are extremely hot — use only with tight
# filters or a secondary script once the 1402 backtrace pinpoints a callsite family.

from __future__ import annotations

import os
import re
import lldb


def _env_int(name: str, default: int) -> int:
    v = os.environ.get(name)
    if v is None or v == "":
        return default
    try:
        return int(v)
    except ValueError:
        return default


def _env_opt_str(name: str) -> str | None:
    v = os.environ.get(name)
    if v is None or v == "":
        return None
    return v


def _eval_signed(frame: lldb.SBFrame, expr: str) -> int | None:
    val = frame.EvaluateExpression(expr)
    if not val.IsValid() or not val.GetError().Success():
        return None
    return val.GetValueAsSigned()


def _macro_path(frame: lldb.SBFrame) -> str:
    val = frame.EvaluateExpression("self->macro_source_path")
    if not val.IsValid():
        return "?"
    summary = val.GetSummary()
    if summary and summary not in ('nil', 'None'):
        s = summary.strip()
        if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
            return s[1:-1]
        return s
    desc = val.GetObjectDescription()
    if desc:
        m = re.search(r'"(/[^"]+)"', desc)
        if m:
            return m.group(1)
        m = re.search(r'(/[^\s`]+(?:\.cr))', desc)
        if m:
            return m.group(1)
    return val.GetValue() or "?"


def _span_line_range(frame: lldb.SBFrame) -> tuple[int | None, int | None]:
    span = frame.FindVariable("span")
    if not span.IsValid():
        return None, None
    sl = span.GetChildMemberWithName("start_line")
    el = span.GetChildMemberWithName("end_line")
    a = sl.GetValueAsSigned() if sl.IsValid() else None
    b = el.GetValueAsSigned() if el.IsValid() else None
    return a, b


def _body_node_ptr(frame: lldb.SBFrame) -> int:
    bn = frame.FindVariable("body_node")
    if not bn.IsValid():
        return 0
    return bn.GetValueAsUnsigned()


def _completion_handler(frame: lldb.SBFrame, bp_loc, extra_args, internal_dict) -> bool:
    substr = _env_opt_str("CRYSTAL_V2_LLDB_MB_FILTER_PATH_SUBSTR")
    pieces_filter = _env_opt_str("CRYSTAL_V2_LLDB_MB_FILTER_PIECES")
    line_start_f = _env_opt_str("CRYSTAL_V2_LLDB_MB_FILTER_START_LINE")
    line_end_f = _env_opt_str("CRYSTAL_V2_LLDB_MB_FILTER_END_LINE")
    max_stops = _env_int("CRYSTAL_V2_LLDB_MB_MAX_STOPS", 0)
    bt_depth = _env_int("CRYSTAL_V2_LLDB_MB_BT_DEPTH", 12)

    pieces_v = frame.FindVariable("pieces_count")
    pieces = pieces_v.GetValueAsSigned() if pieces_v.IsValid() else -1

    start_line, end_line = _span_line_range(frame)
    body_node_ptr = _body_node_ptr(frame)

    out_sz = _eval_signed(frame, "output.bytesize")
    if out_sz is None:
        out_sz = -1

    path = _macro_path(frame)

    if pieces_filter is not None:
        if str(pieces) != pieces_filter.strip():
            return False
    if substr is not None and substr not in path:
        return False
    if line_start_f is not None and start_line is not None:
        if str(start_line) != line_start_f.strip():
            return False
    if line_end_f is not None and end_line is not None:
        if str(end_line) != line_end_f.strip():
            return False

    if not hasattr(_completion_handler, "_count"):
        _completion_handler._count = 0
    _completion_handler._count += 1
    n = _completion_handler._count

    span_s = "?"
    if start_line is not None and end_line is not None:
        span_s = f"L{start_line}-{end_line}"

    print(
        f"\n[macro-body-completion #{n}] path={path!r} span={span_s} pieces_count={pieces} "
        f"body_node=0x{body_node_ptr:x} output_bytesize={out_sz}"
    )
    thread = frame.GetThread()
    print(thread.GetFrameAtIndex(0).GetFunctionName() or "?")
    for d in range(min(bt_depth, thread.GetNumFrames())):
        fr = thread.GetFrameAtIndex(d)
        print(f"  #{d} {fr.GetFunctionName()} @ {fr.GetLineEntry()}")

    if max_stops > 0 and n >= max_stops:
        print(f"[macro-body-completion] reached CRYSTAL_V2_LLDB_MB_MAX_STOPS={max_stops}, stopping.")
        return True
    return False


def macro_body_trace_setup(
    debugger: lldb.SBDebugger, command: str, result: lldb.SBCommandReturnObject, internal_dict
) -> None:
    target = debugger.GetSelectedTarget()
    if not target.IsValid():
        result.AppendMessage("macro-body-trace-setup: no valid target; create target first.")
        return

    # Clear previous hit counter when re-running setup in the same lldb session.
    _completion_handler._count = 0

    bp = target.BreakpointCreateByLocation("macro_expander.cr", 1402)
    bp.SetScriptCallbackFunction("lldb_macro_body_trace._completion_handler")
    msg = (
        f"macro-body-trace: breakpoint on macro_expander.cr:1402 (maybe_record → dump) "
        f"(id={bp.GetID()}), filter_path_substr={_env_opt_str('CRYSTAL_V2_LLDB_MB_FILTER_PATH_SUBSTR')!r} "
        f"filter_pieces={_env_opt_str('CRYSTAL_V2_LLDB_MB_FILTER_PIECES')!r} "
        f"filter_span={_env_opt_str('CRYSTAL_V2_LLDB_MB_FILTER_START_LINE')!r}-"
        f"{_env_opt_str('CRYSTAL_V2_LLDB_MB_FILTER_END_LINE')!r} "
        f"max_stops={_env_int('CRYSTAL_V2_LLDB_MB_MAX_STOPS', 0)}"
    )
    result.AppendMessage(msg)


def __lldb_init_module(debugger: lldb.SBDebugger, internal_dict):
    debugger.HandleCommand(
        "command script add -f lldb_macro_body_trace.macro_body_trace_setup macro-body-trace-setup"
    )
