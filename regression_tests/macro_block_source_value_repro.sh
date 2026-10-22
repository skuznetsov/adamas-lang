#!/usr/bin/env python3
"""Compare source macro block values with the original Crystal compiler."""
from pathlib import Path
import os
import sys
runner = Path(__file__).resolve().parent / "macro_block_source_value_repro/run_original_first.py"
os.execv(sys.executable, [sys.executable, str(runner), *sys.argv[1:]])
