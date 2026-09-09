#!/usr/bin/env python3
"""Add the same AddressSanitizer function attribute to an emitted LLVM file.

Clang's command-line sanitizer pass does not instrument arbitrary IR loads
unless the generated function carries ``sanitize_address``. This helper
applies that attribute uniformly to every function definition. It deliberately
does not alter globals, loads, or control flow.
"""

from pathlib import Path
import re
import sys


DEFINE_RE = re.compile(r"^define .*?\s*\{", re.MULTILINE)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} INPUT.ll OUTPUT.ll", file=sys.stderr)
        return 2

    source_path, output_path = map(Path, sys.argv[1:])
    text = source_path.read_text()
    definitions = DEFINE_RE.findall(text)
    if not definitions:
        raise SystemExit(f"no function definitions in {source_path}")
    if any(" sanitize_address " in definition for definition in definitions):
        raise SystemExit(f"input already contains sanitize_address: {source_path}")

    instrumented, count = re.subn(
        r"^(define .*?)\s*\{",
        r"\1 sanitize_address {",
        text,
        flags=re.MULTILINE,
    )
    if count != len(definitions):
        raise SystemExit(
            f"instrumented {count} definitions, expected {len(definitions)} "
            f"in {source_path}"
        )
    output_path.write_text(instrumented)
    print(f"instrumented {count} definitions: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
