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
# Check source initializer contracts before automatic allocator recovery.
# Unknown or unsupported candidate shapes remain governed by ordinary resolution.
cases = {'ivar_before_proc_positive': ('lib IvarSeparatorBoundaryOracle\n  fun putchar(value : Int32) : Int32\n  fun exit(status : Int32) : NoReturn\nend\n\ndef raise(message : String) : NoReturn\n  IvarSeparatorBoundaryOracle.exit(91_i32)\nend\n\nclass IvarSeparatorBoundaryBox\n  def initialize(@value : Int32, @finalizer : Int32 ->)\n  end\n\n  def value\n    @value\n  end\n\n  def release\n    @finalizer.call(@value)\n  end\nend\n\ndef consume_int32(value : Int32) : Nil\n  IvarSeparatorBoundaryOracle.putchar(value)\n  nil\nend\n\nbox = IvarSeparatorBoundaryBox.new(\n  65_i32,\n  ->(value : Int32) { IvarSeparatorBoundaryOracle.putchar(66_i32); nil }\n)\nconsume_int32(box.value)\nIvarSeparatorBoundaryOracle.putchar(10_i32)\nbox.release\nIvarSeparatorBoundaryOracle.putchar(10_i32)\n', b'A\nB\n'), 'allocator_overload_order_runtime': ('lib AllocatorSourceContractOracle\n  fun putchar(value : Int32) : Int32\n  fun exit(status : Int32) : NoReturn\nend\n\ndef raise(message : String) : NoReturn\n  AllocatorSourceContractOracle.exit(91_i32)\nend\n\nclass AllocatorSourceOverloadBox\n  def initialize(value : String)\n    AllocatorSourceContractOracle.putchar(83_i32)\n  end\n\n  def initialize(value : Int32)\n    AllocatorSourceContractOracle.putchar(65_i32)\n  end\nend\n\nAllocatorSourceOverloadBox.new(65_i32)\nAllocatorSourceContractOracle.putchar(10_i32)\n', b'A\n'), 'allocator_default_argument_runtime': ('lib AllocatorSourceContractOracle\n  fun putchar(value : Int32) : Int32\n  fun exit(status : Int32) : NoReturn\nend\n\ndef raise(message : String) : NoReturn\n  AllocatorSourceContractOracle.exit(91_i32)\nend\n\nclass AllocatorSourceDefaultBox\n  def initialize(@value : Int32, @mark : Int32 = 68_i32)\n  end\n\n  def emit : Nil\n    AllocatorSourceContractOracle.putchar(@mark)\n  end\nend\n\nAllocatorSourceDefaultBox.new(65_i32).emit\nAllocatorSourceContractOracle.putchar(10_i32)\n', b'D\n'), 'allocator_inherited_initializer_runtime': ('lib AllocatorSourceContractOracle\n  fun putchar(value : Int32) : Int32\n  fun exit(status : Int32) : NoReturn\nend\n\ndef raise(message : String) : NoReturn\n  AllocatorSourceContractOracle.exit(91_i32)\nend\n\nclass AllocatorSourceParent\n  def initialize(@value : Int32)\n  end\n\n  def emit : Nil\n    AllocatorSourceContractOracle.putchar(@value)\n    AllocatorSourceContractOracle.putchar(10_i32)\n  end\nend\n\nclass AllocatorSourceChild < AllocatorSourceParent\nend\n\nAllocatorSourceChild.new(72_i32).emit\n', b'H\n'), 'allocator_named_argument_runtime': ('lib AllocatorSourceContractOracle\n  fun putchar(value : Int32) : Int32\n  fun exit(status : Int32) : NoReturn\nend\n\ndef raise(message : String) : NoReturn\n  AllocatorSourceContractOracle.exit(91_i32)\nend\n\nclass AllocatorSourceNamedBox\n  def initialize(@value : Int32, @mark : Int32)\n  end\n\n  def emit : Nil\n    AllocatorSourceContractOracle.putchar(@mark)\n    AllocatorSourceContractOracle.putchar(10_i32)\n  end\nend\n\nAllocatorSourceNamedBox.new(value: 65_i32, mark: 78_i32).emit\n', b'N\n'), 'allocator_generic_initializer_runtime': ('lib AllocatorSourceContractOracle\n  fun putchar(value : Int32) : Int32\n  fun exit(status : Int32) : NoReturn\nend\n\ndef raise(message : String) : NoReturn\n  AllocatorSourceContractOracle.exit(91_i32)\nend\n\nclass AllocatorSourceGenericBox(T)\n  def initialize(@value : T)\n  end\n\n  def emit : Nil\n    AllocatorSourceContractOracle.putchar(@value)\n    AllocatorSourceContractOracle.putchar(10_i32)\n  end\nend\n\nAllocatorSourceGenericBox(Int32).new(71_i32).emit\n', b'G\n'), 'ivar_before_proc_wrong_callback': ('lib IvarSeparatorBoundaryOracle\n  fun exit(status : Int32) : NoReturn\nend\n\ndef raise(message : String) : NoReturn\n  IvarSeparatorBoundaryOracle.exit(91_i32)\nend\n\nclass IvarSeparatorBoundaryBox\n  def initialize(@value : Int32, @finalizer : Int32 ->)\n  end\nend\n\nIvarSeparatorBoundaryBox.new(65_i32, ->(value : String) { nil })\n', None), 'allocator_ordinary_wrong_type_rejected': ('lib AllocatorSourceContractOracle\n  fun putchar(value : Int32) : Int32\n  fun exit(status : Int32) : NoReturn\nend\n\ndef raise(message : String) : NoReturn\n  AllocatorSourceContractOracle.exit(91_i32)\nend\n\nclass AllocatorSourceOrdinaryBox\n  def initialize(@value : Int32)\n  end\nend\n\nAllocatorSourceOrdinaryBox.new("wrong")\n', None)}
negative_patterns = {'ivar_before_proc_wrong_callback': '(?=.*(?:IvarSeparatorBoundaryBox|argument #2|finalizer))(?=.*Proc)(?=.*String)(?=.*Int32)(?=.*(?:no overload|not|must be|expected))', 'allocator_ordinary_wrong_type_rejected': '(?=.*AllocatorSourceOrdinaryBox)(?=.*String)(?=.*Int32)(?=.*(?:no overload|not|must be|expected))'}
work = Path(tempfile.mkdtemp(prefix='adamas_allocator_source_contract_'))
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
            source.write_text(body)
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
                assert re.search(negative_patterns[name].encode(), errors[0], re.I), (stage, name, errors)
                assert not re.search(rb'syntax|unexpected token|expecting token', errors[0], re.I), errors[0]
            else:
                result = subprocess.run([str(safe), str(binary), '5', '512'], env={**env, 'RUN_SAFE_PASSTHROUGH_STDIO': '1'}, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                (work / (stage + '.' + name + '.stdout')).write_bytes(result.stdout)
                (work / (stage + '.' + name + '.stderr')).write_bytes(result.stderr)
                assert result.returncode == 0 and result.stdout == expected, (stage, name, result.returncode, result.stdout, result.stderr)
                footer(result.stderr, 0, exact=True)
            print('PASS[' + stage + ':' + name + ']', flush=True)
        print(stage.upper() + '_PASS_COMPLETE positives=6 negatives=2', flush=True)
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
