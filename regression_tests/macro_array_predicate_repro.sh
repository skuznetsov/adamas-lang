#!/usr/bin/env bash
# Stock-first no-prelude regression for ArrayLiteral#all? and #any? block semantics and argument contracts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export MACRO_ARRAY_PREDICATES_FIXTURES="$SCRIPT_DIR/fixtures/macro_array_predicates"
export MACRO_ARRAY_PREDICATES_ROOT="${ADAMAS_ROOT_DIR:-${ADAMAS_ROOT:-$SCRIPT_DIR/..}}"
exec python3 - "$@" <<'PY_RUNNER'
from pathlib import Path
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

root_hint = os.environ.get('MACRO_ARRAY_PREDICATES_ROOT') or os.environ.get('ADAMAS_ROOT_DIR') or os.environ.get('ADAMAS_ROOT') or os.getcwd()
root = Path(root_hint).resolve()
fixtures = Path(os.environ['MACRO_ARRAY_PREDICATES_FIXTURES'])
safe = Path(os.environ.get('ADAMAS_SAFE_RUNNER', str(root / 'scripts/run_safe.sh')))
original_hint = os.environ.get('ORIGINAL_CRYSTAL_BIN') or os.environ.get('ORIGINAL_CRYSTAL') or 'crystal'
original = Path(shutil.which(original_hint) or original_hint).resolve()
candidate = Path(sys.argv[1] if len(sys.argv) == 2 else os.environ.get('ADAMAS_BIN', str(root / 'bin/adamas'))).resolve()
assert len(sys.argv) <= 2, 'usage: macro_array_predicate_repro.sh [candidate]'
assert safe.is_file() and original.is_file(), 'safe runner and stock Crystal are required'
stock_only = os.environ.get('ORIGINAL_ONLY', '0') == '1'
assert stock_only or candidate.is_file(), 'candidate compiler is required'
for line in (fixtures / 'SHA256SUMS').read_text().splitlines():
    digest, filename = line.split('  ', 1)
    assert Path(filename).name == filename
    assert hashlib.sha256((fixtures / filename).read_bytes()).hexdigest() == digest, filename
cases = json.loads((fixtures / 'cases.json').read_text())
assert {p.stem for p in fixtures.glob('*.cr')} == {c['name'] for c in cases}
work = Path(tempfile.mkdtemp(prefix='macro-array-predicates.'))
(work / 'tmp').mkdir()
(work / 'home').mkdir()
env = {k: os.environ[k] for k in ('PATH', 'LIBRARY_PATH', 'ADAMAS_EXTRA_LINK_FLAGS') if k in os.environ}
env.update(HOME=str(work / 'home'), TMPDIR=str(work / 'tmp'), LANG='C', LC_ALL='C', RUN_SAFE_PASSTHROUGH_STDIO='1', ADAMAS_LLVM_CACHE='0')
stdlib = os.environ.get('ORIGINAL_CRYSTAL_PATH') or os.environ.get('CRYSTAL_PATH')

def footer(raw, expected):
    match = re.search(rb'(?m)^\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit exit_code=([0-9]+) [^\r\n]+\n?\Z', raw)
    assert match and int(match[1]) == int(match[2]) == expected, 'missing successful resource/exit evidence'
    return raw[:match.start()]

def execute(command, log):
    result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=195)
    log.write_bytes(result.stdout + result.stderr)
    return result

success = False
try:
    if not stdlib:
        result = execute([str(safe), str(original), '20', '512', 'env', 'CRYSTAL_PATH'], work / 'stdlib.log')
        assert result.returncode == 0 and not footer(result.stderr, 0)
        stdlib = result.stdout.decode().strip()
    assert any(Path(p).is_dir() for p in stdlib.split(':')), 'stock stdlib path is unavailable'
    env['CRYSTAL_PATH'] = stdlib
    for stage, compiler in [('original', original)] + ([] if stock_only else [('candidate', candidate)]):
        for case in cases:
            name = case['name']
            source = fixtures / (name + '.cr')
            binary = work / (stage + '-' + name + '.bin')
            cache = work / (stage + '-' + name + '.cache')
            cache.mkdir()
            env['CRYSTAL_CACHE_DIR'] = str(cache)
            if stage == 'original':
                flags = shlex.split(os.environ.get('ORIGINAL_CRYSTAL_LINK_FLAGS', '-fuse-ld=/usr/bin/ld' if sys.platform == 'darwin' else ''))
                args = ['build', '--prelude=empty', '--no-debug'] + (['--link-flags=' + ' '.join(flags)] if flags else [])
                args += [str(source), '-o', str(binary)]
            else:
                args = [str(source), '--no-prelude', '--no-debug', '--no-ast-cache', '--no-llvm-cache', '-o', str(binary)]
            result = execute([str(safe), str(compiler), '180', '8192', *args], work / (stage + '-' + name + '.compile.log'))
            shutil.rmtree(cache)
            if case['ok']:
                assert result.returncode == 0 and binary.is_file(), (stage, name, 'compile failed')
                footer(result.stderr, 0)
                runtime = execute([str(safe), str(binary), '5', '512'], work / (stage + '-' + name + '.run.log'))
                assert runtime.returncode == 0 and not footer(runtime.stderr, 0), (stage, name, 'runtime failed')
                assert runtime.stdout == (fixtures / (name + '.expected')).read_bytes(), (stage, name, runtime.stdout)
            else:
                assert result.returncode == 1 and not binary.exists(), (stage, name, 'expected strict rejection')
                footer(result.stderr, 1)
                diagnostic = (result.stdout + result.stderr).decode(errors='replace')
                tokens = case['original_diagnostic'] if stage == 'original' else case['candidate_diagnostic']
                assert all(token in diagnostic for token in tokens), (stage, name, 'wrong rejection identity')
                assert re.search(r'(?im)^(?:error|Error)[:\[]', diagnostic), (stage, name, 'expected compiler diagnostic')
            if binary.exists():
                binary.unlink()
            print(f'PASS {stage} {name}', flush=True)
    success = True
finally:
    for path in work.glob('*.cache'):
        shutil.rmtree(path)
    for path in work.glob('*.bin'):
        path.unlink()
    if success and os.environ.get('KEEP_ARTIFACTS') != '1':
        shutil.rmtree(work)
    else:
        print(f'kept_artifacts={work}', file=sys.stderr)
PY_RUNNER
