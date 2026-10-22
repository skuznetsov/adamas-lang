#!/usr/bin/env python3
"""Run every original-first suite, retain failures, and fail the full matrix."""
from pathlib import Path
import subprocess
import sys
root=Path(__file__).resolve().parent
assert len(sys.argv)==2
failures=[]
for name in ("strict","capture","capture_binding","unpack","arrow","raw_call","c_callback","return_scope","begin_flow","exception_semantic","literal_result","extern_types","annotations","macro_unpack"):
 print("SUITE["+name+"]",flush=True)
 status=subprocess.run([sys.executable,str(root/name/"run.py"),sys.argv[1]]).returncode
 if status:
  failures.append((name,status))
  print("SUITE_FAIL["+name+"]="+str(status),flush=True)
assert not failures, failures
print("PASS_COMPLETE[proc_source_contract_matrix]",flush=True)
