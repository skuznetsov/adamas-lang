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
prefix = '''lib IvarBoundaryOracle
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
def raise(message : String) : NoReturn
  IvarBoundaryOracle.exit(91_i32)
end
def consume_int32(value : Int32) : Nil
  IvarBoundaryOracle.putchar(value)
  nil
end
'''
def box(restriction):
    return '''class IvarBoundaryBox
  def initialize(@value : Int32, @finalizer : ''' + restriction + ''')
  end
  def value
    @value
  end
  def release
    @finalizer.call(@value)
  end
end
box = IvarBoundaryBox.new(65_i32, ->(value : Int32) { consume_int32(66_i32); nil })
'''
release = '''consume_int32(box.value)
IvarBoundaryOracle.putchar(10_i32)
box.release
IvarBoundaryOracle.putchar(10_i32)
'''
cases = {
    'ivar_before_proc': (box('Int32 ->') + release, b'A\nB\n'),
    'explicit_proc_type': (box('Proc(Int32, Nil)') + release, b'A\nB\n'),
    'multiple_ivars_before_proc': ('''class MultipleIvarBoundaryBox
  def initialize(@first : Int32, @second : Int32, @finalizer : Int32 ->)
  end
  def first
    @first
  end
  def second
    @second
  end
  def release
    @finalizer.call(@first)
  end
end
box = MultipleIvarBoundaryBox.new(65_i32, 66_i32, ->(value : Int32) { consume_int32(67_i32); nil })
consume_int32(box.first)
consume_int32(box.second)
IvarBoundaryOracle.putchar(10_i32)
box.release
IvarBoundaryOracle.putchar(10_i32)
''', b'AB\nC\n'),
    # The opposite control checks the recovered ivar's exact source type.
    # Constructor Proc-input admission is a separate, recorded open defect.
    'wrong_ivar_consumer': (box('Int32 ->') + '''def consume_string(value : String) : Nil
  nil
end
consume_string(box.value)
''', None),
}
work = Path(tempfile.mkdtemp(prefix='adamas_implicit_ivar_boundary_'))
passed = False

def footer(raw, code, exact=False):
    end = re.search(rb'(?m)^\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 [^\r\n]*\n?\Z', raw)
    assert end, raw[-2000:]
    fields = dict(part.split(b'=', 1) for part in end.group(0).split()[1:])
    assert fields.get(b'outcome') == b'exit' and fields.get(b'reason') == b'exit' and fields.get(b'exit_code') == str(code).encode(), raw[-2000:]
    exit_line = re.search(rb'(?m)^\[EXIT: ' + str(code).encode() + rb'\] after ~[0-9]+(?:\.[0-9]+)? ?s\r?\n?\Z', raw[:end.start()])
    assert exit_line and (not exact or exit_line.start() == 0), raw[-2000:]

try:
    env = os.environ.copy()
    if not env.get('CRYSTAL_PATH'):
        result = subprocess.run([str(safe), str(original), '10', '1024', 'env', 'CRYSTAL_PATH'], env={**env, 'RUN_SAFE_PASSTHROUGH_STDIO': '1'}, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode == 0, result.stderr
        footer(result.stderr, 0, exact=True)
        env['CRYSTAL_PATH'] = result.stdout.decode().strip()
    for stage, compiler in [('original', original), ('candidate', candidate)]:
        for name, (body, expected) in cases.items():
            source = work / (name + '.cr')
            source.write_text(prefix + body)
            binary = work / (stage + '.' + name + '.program')
            cache = work / (stage + '.' + name + '.cache')
            cache.mkdir()
            args = ['build', '--no-debug', '--prelude=empty'] if stage == 'original' else []
            if stage == 'original' and sys.platform == 'darwin':
                args.append('--link-flags=-fuse-ld=/usr/bin/ld')
            args += [str(source), '-o', str(binary)]
            if stage == 'candidate':
                args += ['--no-prelude', '--no-debug', '--no-ast-cache', '--no-llvm-cache']
            result = subprocess.run([str(safe), str(compiler), '120', '4096', *args], env={**env, 'CRYSTAL_CACHE_DIR': str(cache), 'ADAMAS_LLVM_CACHE': '0'}, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            (work / (stage + '.' + name + '.compile.log')).write_bytes(result.stdout)
            shutil.rmtree(cache)
            code = 1 if expected is None else 0
            assert result.returncode == code, (stage, name, result.stdout[-4000:])
            footer(result.stdout, code)
            if expected is None:
                assert not binary.exists(), (stage, name, 'negative produced a binary')
                errors = re.findall(rb'(?im)^\s*error:[^\r\n]*', result.stdout)
                assert errors, (stage, name, result.stdout[-2000:])
                assert re.search(rb'(?:consume_string.*Int32|must be String, not Int32)', errors[0], re.I), (stage, name, errors)
                assert not re.search(rb'syntax|unexpected token|expecting token', errors[0], re.I), errors[0]
            else:
                result = subprocess.run([str(safe), str(binary), '5', '512'], env={**env, 'RUN_SAFE_PASSTHROUGH_STDIO': '1'}, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                (work / (stage + '.' + name + '.stdout')).write_bytes(result.stdout)
                (work / (stage + '.' + name + '.stderr')).write_bytes(result.stderr)
                assert result.returncode == 0 and result.stdout == expected, (stage, name, result.returncode, result.stdout, result.stderr)
                footer(result.stderr, 0, exact=True)
            print('PASS[' + stage + ':' + name + ']', flush=True)
        print(stage.upper() + '_PASS_COMPLETE positives=3 negatives=1', flush=True)
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
