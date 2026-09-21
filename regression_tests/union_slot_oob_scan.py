#!/usr/bin/env python3
"""Scan emitted LLVM IR for union reinterpret slots that are read past their end.

Detects the `alloca <src union>` / `load <dst union>` pattern where the loaded
type is wider than the allocated one: a stack out-of-bounds read.
"""
import re, sys

TYPEDEF = re.compile(r'^(%[\w$.]+)\s*=\s*type\s*\{\s*i32\s*,\s*\[(\d+)\s*x\s*i(\d+)\]\s*\}')
ALLOCA  = re.compile(r'^\s*(%[\w$.]+)\s*=\s*alloca\s+(%[\w$.]+)\s*(?:,|$)')
LOAD    = re.compile(r'^\s*(%[\w$.]+)\s*=\s*load\s+(%[\w$.]+)\s*,\s*ptr\s+(%[\w$.]+)')
FUNC    = re.compile(r'^define\s.*?@"?([\w$.]+)"?\(')

def scan(path):
    sizes, hits = {}, []
    slot = {}
    func = "<module>"
    with open(path, errors="replace") as fh:
        for lineno, line in enumerate(fh, 1):
            m = TYPEDEF.match(line)
            if m:
                sizes[m.group(1)] = 4 + int(m.group(2)) * (int(m.group(3)) // 8)
                continue
            m = FUNC.match(line)
            if m:
                func, slot = m.group(1), {}
                continue
            m = ALLOCA.match(line)
            if m:
                slot[m.group(1)] = (m.group(2), lineno)
                continue
            m = LOAD.match(line)
            if m:
                dst, src = m.group(2), slot.get(m.group(3))
                if src and src[0] in sizes and dst in sizes and sizes[dst] > sizes[src[0]]:
                    hits.append((func, lineno, m.group(3), src[0], sizes[src[0]], dst, sizes[dst]))
    return hits

total = 0
for path in sys.argv[1:]:
    for func, lineno, name, src, ssz, dst, dsz in scan(path):
        total += 1
        print(f"{path}:{lineno}: OOB_UNION_SLOT func={func} slot={name} alloca={src}({ssz}B) load={dst}({dsz}B) over={dsz-ssz}B")
print(f"[scan] files={len(sys.argv)-1} oob_union_slots={total}")
sys.exit(1 if total else 0)
