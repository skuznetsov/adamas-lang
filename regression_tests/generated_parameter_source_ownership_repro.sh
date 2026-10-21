#!/usr/bin/env bash
set -euo pipefail
ROOT="${ADAMAS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
export ADAMAS_ROOT="$ROOT"
export PARAMETER_SOURCE_FIXTURES="${PARAMETER_SOURCE_FIXTURES:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/generated_parameter_source_ownership_fixtures}"
exec python3 - "${1:-$ROOT/bin/adamas}" <<'PY'
from pathlib import Path
import os, re, shutil, subprocess, sys, tempfile

root = Path(os.environ['ADAMAS_ROOT'])
safe = Path(os.environ.get('ADAMAS_RUN_SAFE', str(root / 'scripts/run_safe.sh')))
original_name = os.environ.get('ORIGINAL_CRYSTAL_BIN', 'crystal')
original = Path(shutil.which(original_name) or original_name)
candidate = Path(sys.argv[1]).resolve()
fixtures = Path(os.environ['PARAMETER_SOURCE_FIXTURES'])
assert all(p.is_file() and os.access(p, os.X_OK) for p in (safe, original, candidate))
cases = sorted(fixtures.glob('*.cr'))
assert cases
work = Path(tempfile.mkdtemp(prefix='adamas_generated_parameter_source_'))
passed = False

def footer(raw, code, exact=False):
    end = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
    assert end, raw[-2000:]
    pairs = [part.split(b'=', 1) for part in end.group(0).split()[1:]]
    assert all(len(pair) == 2 for pair in pairs), raw[-2000:]
    fields = dict(pairs)
    assert len(fields) == len(pairs), raw[-2000:]
    assert fields.get(b'outcome') == b'exit' and fields.get(b'reason') == b'exit' and fields.get(b'exit_code') == str(code).encode(), raw[-2000:]
    exit_line = re.search(rb'(?m)^\[EXIT: ' + str(code).encode() + rb'\] after ~[0-9]+(?:\.[0-9]+)? ?s\r?\n?\Z', raw[:end.start()])
    assert exit_line and (not exact or exit_line.start() == 0), raw[-2000:]

def primary_error(raw):
    for line in raw.decode(errors='replace').splitlines():
        match = re.match(r'^\s*error:\s*(.*)$', line, re.I)
        if match and not re.match(r'^instantiating\b', match.group(1), re.I):
            return line
    return ''

try:
    env = os.environ.copy()
    if not env.get('CRYSTAL_PATH'):
        result = subprocess.run([str(safe), str(original), '10', '1024', 'env', 'CRYSTAL_PATH'], env={**env, 'RUN_SAFE_PASSTHROUGH_STDIO': '1'}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        assert result.returncode == 0, result.stderr
        footer(result.stderr, 0, exact=True)
        env['CRYSTAL_PATH'] = result.stdout.decode().strip()
    for stage, compiler in [('original', original), ('candidate', candidate)]:
        positives = negatives = 0
        for source in cases:
            name = source.stem
            expected_path = source.with_suffix('.expected')
            reject_path = source.with_suffix('.reject')
            assert expected_path.is_file() != reject_path.is_file(), name
            expected = expected_path.read_bytes() if expected_path.is_file() else None
            binary = work / (stage + '.' + name + '.program')
            cache = work / (stage + '.' + name + '.cache')
            cache.mkdir()
            if stage == 'original':
                args = ['build', '--no-debug', '--error-trace', '--prelude=empty']
                if sys.platform == 'darwin':
                    args.append('--link-flags=-fuse-ld=/usr/bin/ld')
                args += [str(source), '-o', str(binary)]
            else:
                args = [str(source), '--no-prelude', '--no-debug', '--no-ast-cache', '--no-llvm-cache', '-o', str(binary)]
            result = subprocess.run([str(safe), str(compiler), '120', '4096', *args], env={**env, 'CRYSTAL_CACHE_DIR': str(cache), 'ADAMAS_LLVM_CACHE': '0'}, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145)
            (work / (stage + '.' + name + '.compile.log')).write_bytes(result.stdout)
            shutil.rmtree(cache)
            code = 1 if expected is None else 0
            assert result.returncode == code, (stage, name, result.returncode, result.stdout[-5000:])
            footer(result.stdout, code)
            if expected is None:
                assert not binary.exists(), (stage, name, 'negative produced a binary')
                error = primary_error(result.stdout)
                assert error and not re.search(r'syntax error|unexpected token|unterminated|unclosed|internal compiler error', error, re.I), error
                assert re.search(reject_path.read_text().strip(), error), (stage, name, error)
                negatives += 1
            else:
                assert binary.is_file(), (stage, name, 'missing executable')
                result = subprocess.run([str(safe), str(binary), '5', '512'], env={**env, 'RUN_SAFE_PASSTHROUGH_STDIO': '1'}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
                (work / (stage + '.' + name + '.stdout')).write_bytes(result.stdout)
                (work / (stage + '.' + name + '.stderr')).write_bytes(result.stderr)
                assert result.returncode == 0 and result.stdout == expected, (stage, name, result.returncode, result.stdout, result.stderr)
                footer(result.stderr, 0, exact=True)
                binary.unlink()
                positives += 1
            print('PASS[' + stage + ':' + name + ']', flush=True)
        print(stage.upper() + '_PASS_COMPLETE positives=' + str(positives) + ' negatives=' + str(negatives), flush=True)
    passed = True
finally:
    for path in work.glob('*.cache'):
        shutil.rmtree(path)
    for path in work.glob('*.program'):
        path.unlink()
    if passed and os.environ.get('KEEP_ARTIFACTS') != '1':
        shutil.rmtree(work)
    else:
        print('kept_artifacts=' + str(work), file=sys.stderr)
PY
