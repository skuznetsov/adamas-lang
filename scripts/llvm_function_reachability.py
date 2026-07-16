#!/usr/bin/env python3
"""Static LLVM function-reference and reachability census.

This module intentionally performs triage, not linker-equivalent liveness
analysis.  It streams the LLVM input, records direct ``@symbol`` references in
function bodies separately from module-level/global initializer references,
and follows references from the conventional Crystal entry points plus all
known global initializer targets.  Function-pointer tables are therefore
conservatively retained, while unresolved/indirect behavior remains explicit
in the report rather than being guessed away.
"""

from __future__ import annotations

import argparse
import collections
import dataclasses
import json
import re
import sys
from pathlib import Path
from typing import Iterable


DEFAULT_ROOTS: tuple[str, ...] = ("main", "__crystal_main", "__adamas_main")

# LLVM identifiers are either quoted strings (with escaped bytes) or an
# unquoted token.  The latter is deliberately broad: Crystal's Adamas names
# contain '$', '.', and other punctuation that a C identifier regex would drop.
FUNCTION_HEADER_RE = re.compile(
    r"^\s*(?P<kind>define|declare)\b(?P<prefix>.*?)\s@"
    r"(?P<name>\"(?:\\.|[^\"\\])*\"|[^\s(),{}\[\]\"]+)\s*\(",
)
COMMENT_RE = re.compile(r"^\s*;")

LINKAGE_WORDS = frozenset(
    {
        "available_externally",
        "common",
        "dllimport",
        "dllexport",
        "extern_weak",
        "external",
        "internal",
        "linkonce",
        "linkonce_odr",
        "private",
        "weak",
        "weak_odr",
    }
)


def decode_llvm_identifier(value: str) -> str:
    """Decode an LLVM quoted identifier without losing unknown escapes."""

    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        value = value[1:-1]

    def decode_byte(match: re.Match[str]) -> str:
        try:
            return chr(int(match.group(1), 16))
        except ValueError:
            return match.group(0)

    return re.sub(r"\\([0-9A-Fa-f]{2})", decode_byte, value)


def _linkage(prefix: str) -> str:
    for token in prefix.split():
        if token in LINKAGE_WORDS:
            return token
    # LLVM's omitted linkage is the external/default linkage.  Keeping this
    # explicit makes linkage counts and TSV comparisons useful instead of
    # conflating a default symbol with an unknown parser result.
    return "external"


def _references(text: str) -> Iterable[str]:
    """Yield LLVM symbol references while skipping ``@`` in string literals."""

    i = 0
    length = len(text)
    delimiters = frozenset("\t\r\n (),{}[];\"")
    while i < length:
        character = text[i]
        if character == ";":
            # LLVM comments run to end-of-line.  A caller already strips full
            # comment lines, but this also protects trailing comments.
            return
        if character == '"':
            # Skip an ordinary LLVM string constant.  Hex escapes occupy three
            # bytes (backslash + two hex digits); all other escapes occupy two.
            i += 1
            while i < length:
                if text[i] == "\\":
                    i += 3 if i + 2 < length and all(c in "0123456789abcdefABCDEF" for c in text[i + 1 : i + 3]) else 2
                elif text[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
            continue
        if character != "@":
            i += 1
            continue

        i += 1
        if i < length and text[i] == '"':
            start = i
            i += 1
            while i < length:
                if text[i] == "\\":
                    i += 3 if i + 2 < length and all(c in "0123456789abcdefABCDEF" for c in text[i + 1 : i + 3]) else 2
                elif text[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
            yield decode_llvm_identifier(text[start:i])
            continue

        start = i
        while i < length and text[i] not in delimiters:
            i += 1
        if start < i:
            yield decode_llvm_identifier(text[start:i])


def _is_function_close(line: str) -> bool:
    # A function body closes with a line whose first token is '}'.  Looking at
    # the first token avoids treating braces inside a string constant as body
    # delimiters and works for LLVM's optional trailing comments/attributes.
    return bool(re.match(r"^\s*}\s*(?:;.*)?$", line))


@dataclasses.dataclass(frozen=True)
class FunctionRecord:
    raw: str
    kind: str  # ``define`` or ``declare``
    linkage: str
    line: int

    @property
    def body_kind(self) -> str:
        return "body" if self.kind == "define" else "declaration"


@dataclasses.dataclass(frozen=True)
class BodyEdge:
    caller: str
    target: str
    count: int

    @property
    def caller_kind(self) -> str:
        return "vdispatch" if self.caller.startswith("__vdispatch__") else "source"


@dataclasses.dataclass(frozen=True)
class GlobalReference:
    target: str
    line: int
    count: int


@dataclasses.dataclass(frozen=True)
class FunctionReport:
    record: FunctionRecord
    reachable: bool
    incoming_callers: tuple[str, ...]
    incoming_source_callers: tuple[str, ...]
    incoming_vdispatch_callers: tuple[str, ...]
    global_ref_count: int
    global_ref_lines: tuple[int, ...]


@dataclasses.dataclass(frozen=True)
class ParsedModule:
    path: str
    functions: tuple[FunctionRecord, ...]
    body_edges: tuple[BodyEdge, ...]
    global_refs: tuple[GlobalReference, ...]


@dataclasses.dataclass(frozen=True)
class ReachabilityReport:
    module: str
    roots_requested: tuple[str, ...]
    roots_present: tuple[str, ...]
    global_roots: tuple[str, ...]
    reachable_symbols: frozenset[str]
    functions: tuple[FunctionReport, ...]
    body_edges: tuple[BodyEdge, ...]
    global_refs: tuple[GlobalReference, ...]

    @property
    def definitions(self) -> tuple[FunctionReport, ...]:
        return tuple(row for row in self.functions if row.record.kind == "define")

    @property
    def declarations(self) -> tuple[FunctionReport, ...]:
        return tuple(row for row in self.functions if row.record.kind == "declare")


def parse_module(path: str | Path) -> ParsedModule:
    """Stream an LLVM file and collect function-body/global reference counters."""

    source_path = Path(path)
    functions: dict[str, FunctionRecord] = {}
    body_edge_counts: collections.Counter[tuple[str, str]] = collections.Counter()
    global_ref_counts: collections.Counter[tuple[str, int]] = collections.Counter()
    current: str | None = None

    def add_body_refs(text: str, line: int, caller: str) -> None:
        for target in _references(text):
            body_edge_counts[(caller, target)] += 1

    with source_path.open("r", encoding="utf-8", errors="replace") as stream:
        for line_number, line in enumerate(stream, 1):
            header = FUNCTION_HEADER_RE.match(line)
            if current is None and header:
                raw = decode_llvm_identifier(header.group("name"))
                kind = header.group("kind")
                record = FunctionRecord(raw=raw, kind=kind, linkage=_linkage(header.group("prefix")), line=line_number)
                # A declaration may be followed by a definition of the same
                # symbol in hand-written fixtures.  Prefer the body-bearing
                # record while retaining deterministic first-seen ordering.
                previous = functions.get(raw)
                if previous is None or (previous.kind == "declare" and kind == "define"):
                    functions[raw] = record
                if kind == "declare":
                    continue

                current = raw
                opening = line.find("{", header.end())
                if opening >= 0:
                    # Attributes between the parameter list and opening brace
                    # may carry address-taken symbols (notably `personality
                    # ptr @__gxx_personality_v0`).  Treat them as caller edges
                    # so required declarations are not falsely reported dead.
                    add_body_refs(line[header.end() : opening], line_number, raw)
                    tail = line[opening + 1 :]
                    closing = tail.find("}")
                    if closing >= 0:
                        add_body_refs(tail[:closing], line_number, raw)
                        current = None
                    else:
                        add_body_refs(tail, line_number, raw)
                continue

            if current is not None:
                if _is_function_close(line):
                    current = None
                elif COMMENT_RE.match(line):
                    continue
                else:
                    add_body_refs(line, line_number, current)
                continue

            # Every module-level @ reference is kept as a conservative global
            # root.  This includes llvm.used/llvm.compiler.used and metadata
            # tables; false positives are safer than deleting address-taken
            # functions during triage.
            if COMMENT_RE.match(line):
                continue
            for target in _references(line):
                global_ref_counts[(target, line_number)] += 1

    ordered_functions = tuple(sorted(functions.values(), key=lambda row: (row.raw, row.kind, row.line)))
    ordered_edges = tuple(
        BodyEdge(caller=caller, target=target, count=count)
        for (caller, target), count in sorted(body_edge_counts.items())
    )
    ordered_globals = tuple(
        GlobalReference(target=target, line=line, count=count)
        for (target, line), count in sorted(global_ref_counts.items(), key=lambda item: (item[0][0], item[0][1]))
    )
    return ParsedModule(str(source_path), ordered_functions, ordered_edges, ordered_globals)


def analyze_module(
    module: ParsedModule,
    roots: Iterable[str] = DEFAULT_ROOTS,
) -> ReachabilityReport:
    """Build a direct-reference graph and conservative reachability closure."""

    roots_tuple = tuple(dict.fromkeys(roots))
    functions_by_name = {record.raw: record for record in module.functions}
    incoming: dict[str, set[str]] = collections.defaultdict(set)
    outgoing: dict[str, set[str]] = collections.defaultdict(set)
    for edge in module.body_edges:
        if edge.caller in functions_by_name and edge.target in functions_by_name:
            incoming[edge.target].add(edge.caller)
            outgoing[edge.caller].add(edge.target)

    global_ref_by_target: dict[str, list[GlobalReference]] = collections.defaultdict(list)
    for reference in module.global_refs:
        global_ref_by_target[reference.target].append(reference)

    roots_present = {root for root in roots_tuple if root in functions_by_name}
    global_roots = {target for target in global_ref_by_target if target in functions_by_name}
    reachable = set(roots_present) | global_roots
    pending = list(sorted(reachable))
    while pending:
        caller = pending.pop()
        for target in sorted(outgoing.get(caller, ())):
            if target not in reachable:
                reachable.add(target)
                pending.append(target)

    reports: list[FunctionReport] = []
    for record in module.functions:
        callers = tuple(sorted(incoming.get(record.raw, ())))
        source_callers = tuple(caller for caller in callers if not caller.startswith("__vdispatch__"))
        vdispatch_callers = tuple(caller for caller in callers if caller.startswith("__vdispatch__"))
        global_refs = tuple(global_ref_by_target.get(record.raw, ()))
        reports.append(
            FunctionReport(
                record=record,
                reachable=record.raw in reachable,
                incoming_callers=callers,
                incoming_source_callers=source_callers,
                incoming_vdispatch_callers=vdispatch_callers,
                global_ref_count=sum(ref.count for ref in global_refs),
                global_ref_lines=tuple(sorted({ref.line for ref in global_refs})),
            )
        )
    return ReachabilityReport(
        module=module.path,
        roots_requested=roots_tuple,
        roots_present=tuple(sorted(roots_present)),
        global_roots=tuple(sorted(global_roots)),
        reachable_symbols=frozenset(reachable),
        functions=tuple(reports),
        body_edges=module.body_edges,
        global_refs=module.global_refs,
    )


def _join(values: Iterable[object]) -> str:
    return ";".join(str(value) for value in values)


def write_tsv(report: ReachabilityReport, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "functions.tsv").open("w", encoding="utf-8", newline="") as stream:
        stream.write(
            "raw\tkind\tbody_kind\tlinkage\tline\treachable\t"
            "incoming_unique_callers\tincoming_source_callers\t"
            "incoming_vdispatch_callers\tglobal_ref_count\tglobal_ref_lines\n"
        )
        for row in report.functions:
            record = row.record
            stream.write(
                "\t".join(
                    (
                        record.raw,
                        record.kind,
                        record.body_kind,
                        record.linkage,
                        str(record.line),
                        "true" if row.reachable else "false",
                        _join(row.incoming_callers),
                        _join(row.incoming_source_callers),
                        _join(row.incoming_vdispatch_callers),
                        str(row.global_ref_count),
                        _join(row.global_ref_lines),
                    )
                )
                + "\n"
            )

    with (out_dir / "edges.tsv").open("w", encoding="utf-8", newline="") as stream:
        stream.write("caller\ttarget\tcaller_kind\tcount\n")
        for edge in report.body_edges:
            stream.write(f"{edge.caller}\t{edge.target}\t{edge.caller_kind}\t{edge.count}\n")

    with (out_dir / "global_refs.tsv").open("w", encoding="utf-8", newline="") as stream:
        stream.write("target\tline\tcount\tknown_function\n")
        known = {row.record.raw for row in report.functions}
        for reference in report.global_refs:
            stream.write(
                f"{reference.target}\t{reference.line}\t{reference.count}\t"
                f"{'true' if reference.target in known else 'false'}\n"
            )


def summary_dict(report: ReachabilityReport) -> dict[str, object]:
    definitions = sum(row.record.kind == "define" for row in report.functions)
    declarations = sum(row.record.kind == "declare" for row in report.functions)
    reachable_definitions = sum(row.record.kind == "define" and row.reachable for row in report.functions)
    reachable_declarations = sum(row.record.kind == "declare" and row.reachable for row in report.functions)
    linkage_counts = collections.Counter(row.record.linkage for row in report.functions)
    global_reference_count = sum(reference.count for reference in report.global_refs)
    global_targets = {reference.target for reference in report.global_refs}
    known = {row.record.raw for row in report.functions}
    return {
        "schema": 1,
        "module": report.module,
        "roots_requested": list(report.roots_requested),
        "roots_present": list(report.roots_present),
        "global_roots": list(report.global_roots),
        "functions": {
            "define": definitions,
            "declare": declarations,
            "total": len(report.functions),
        },
        "linkage": dict(sorted(linkage_counts.items())),
        "reachable": {
            "symbols": len(report.reachable_symbols),
            "definitions": reachable_definitions,
            "declarations": reachable_declarations,
        },
        "body_edges": {
            "unique": len(report.body_edges),
            "references": sum(edge.count for edge in report.body_edges),
        },
        "global_refs": {
            "references": global_reference_count,
            "unique_targets": len(global_targets),
            "known_function_targets": len(global_targets & known),
        },
    }


def write_outputs(report: ReachabilityReport, out_dir: Path) -> None:
    write_tsv(report, out_dir)
    with (out_dir / "summary.json").open("w", encoding="utf-8") as stream:
        json.dump(summary_dict(report), stream, indent=2, sort_keys=True)
        stream.write("\n")


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ll", required=True, help="LLVM IR input")
    parser.add_argument("--out-dir", required=True, help="directory for deterministic TSV/JSON outputs")
    parser.add_argument(
        "--root",
        action="append",
        default=[],
        help="additional root symbol (the Crystal entry roots are always included)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_argument_parser()
    args = parser.parse_args(argv)
    try:
        module = parse_module(args.ll)
        roots = tuple(dict.fromkeys((*DEFAULT_ROOTS, *args.root)))
        report = analyze_module(module, roots)
        write_outputs(report, Path(args.out_dir))
    except (OSError, ValueError) as error:
        print(f"llvm_function_reachability: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
