#!/usr/bin/env bash
set -euo pipefail
ROOT="${ADAMAS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
export ADAMAS_ROOT="$ROOT"
exec python3 - "${1:-$ROOT/bin/adamas}" <<'PY'
from pathlib import Path
import os, re, shutil, subprocess, sys, tempfile

root = Path(os.environ['ADAMAS_ROOT'])
safe = Path(os.environ.get('ADAMAS_RUN_SAFE', str(root / 'scripts/run_safe.sh')))
original = Path(shutil.which(os.environ.get('ORIGINAL_CRYSTAL_BIN', 'crystal')) or '')
candidate = Path(sys.argv[1]).resolve()
assert safe.is_file() and original.is_file() and candidate.is_file()
common = '''lib GroupingOracle
  fun putchar(value : Int32) : Int32
end
macro yielded
  {{yield}}
end
macro assigned
  value = {{yield}}
  emit(value)
end
macro nested_assigned
  left = right = {{yield}}
  emit(left)
  emit(right)
end
macro argument_yield
  emit({{yield}})
end
def emit(value : Int32)
  GroupingOracle.putchar(value)
end
'''
cases = {
    'assignment': ('''assigned do
  false
  65_i32
end
''', b'A'),
    'nested_assignment': ('''nested_assigned do
  false
  66_i32
end
''', b'BB'),
    'argument': ('''argument_yield do
  false
  67_i32
end
''', b'C'),
    'statement': ('''yielded do
  emit(68_i32)
  emit(69_i32)
end
''', b'DE'),
    'single_and_empty': ('''value = yielded do
  70_i32
end
emit(value)
yielded do
end
emit(71_i32)
''', b'FG'),
    'last_expression_type_rejected': ('''assigned do
  65_i32
  false
end
''', None),
}
work = Path(tempfile.mkdtemp(prefix='adamas_macro_yield_grouping_'))
passed = False

def footer(raw, code):
    assert re.search(rb'(?m)^\[EXIT: ' + str(code).encode() + rb'\] after ~[0-9.]+ ?s\r?\n', raw), raw[-2000:]
    assert re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 .*outcome=exit.*reason=exit.*exit_code=' + str(code).encode() + rb'(?: |\r?\n|$)', raw), raw[-2000:]

try:
    env = os.environ.copy()
    if not env.get('CRYSTAL_PATH'):
        result = subprocess.run([str(safe), str(original), '10', '1024', 'env', 'CRYSTAL_PATH'], env={**env, 'RUN_SAFE_PASSTHROUGH_STDIO': '1'}, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode == 0, result.stderr
        footer(result.stderr, 0)
        env['CRYSTAL_PATH'] = result.stdout.decode().strip()
    for stage, compiler in [('original', original), ('candidate', candidate)]:
        for name, (body, expected) in cases.items():
            source = work / (name + '.cr')
            source.write_text(common + body)
            binary = work / (stage + '.' + name + '.program')
            cache = work / (stage + '.' + name + '.cache')
            cache.mkdir()
            compile_env = {**env, 'CRYSTAL_CACHE_DIR': str(cache), 'ADAMAS_LLVM_CACHE': '0'}
            if stage == 'original':
                args = ['build', '--no-debug', '--prelude=empty']
                if sys.platform == 'darwin':
                    args.append('--link-flags=-fuse-ld=/usr/bin/ld')
                args += [str(source), '-o', str(binary)]
            else:
                args = [str(source), '--no-prelude', '--no-debug', '--no-ast-cache', '--no-llvm-cache', '-o', str(binary)]
            result = subprocess.run([str(safe), str(compiler), '120', '4096', *args], env=compile_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            (work / (stage + '.' + name + '.compile.log')).write_bytes(result.stdout)
            shutil.rmtree(cache)
            code = 1 if expected is None else 0
            assert result.returncode == code, (stage, name, result.stdout[-5000:])
            footer(result.stdout, code)
            if expected is None:
                assert not binary.exists(), (stage, name, 'negative produced a binary')
                errors = re.findall(rb'(?im)^\s*error:[^\r\n]*', result.stdout)
                assert errors and re.search(rb'(?:must be|expected|argument types).*?(?:Int32.*Bool|Bool.*Int32)', errors[0], re.I), (stage, name, errors)
                assert not re.search(rb'syntax|unexpected token|expecting token', errors[0], re.I), errors[0]
            else:
                result = subprocess.run([str(safe), str(binary), '5', '512'], env={**env, 'RUN_SAFE_PASSTHROUGH_STDIO': '1'}, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                (work / (stage + '.' + name + '.stdout')).write_bytes(result.stdout)
                (work / (stage + '.' + name + '.stderr')).write_bytes(result.stderr)
                assert result.returncode == 0 and result.stdout == expected, (stage, name, result.returncode, result.stdout, result.stderr)
                footer(result.stderr, 0)
            print('PASS[' + stage + ':' + name + ']', flush=True)
        print(stage.upper() + '_PASS_COMPLETE positives=5 negatives=1', flush=True)
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
