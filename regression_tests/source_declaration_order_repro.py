#!/usr/bin/env python3
"""Compare source registration order across require boundaries with original Crystal.

Run every original case before admitting the candidate stage. Native compilation
and execution are serial and bounded by scripts/run_safe.sh. Successful runs
delete their temporary artifacts; failed runs retain only small evidence files.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(os.environ.get('ADAMAS_REPO_ROOT', os.environ.get('ADAMAS_ROOT', str(Path.cwd()))))
FIXTURES = Path(os.environ.get('ADAMAS_SOURCE_DECLARATION_FIXTURES', str(Path(__file__).resolve().parent / 'source_declaration_order')))
SAFE = Path(os.environ.get('ADAMAS_RUN_SAFE', str(ROOT / 'scripts/run_safe.sh')))
original_name = os.environ.get('ORIGINAL_CRYSTAL_BIN') or os.environ.get('ORIGINAL_CRYSTAL') or 'crystal'
PINNED = Path(shutil.which(original_name) or original_name).resolve()
EXIT_LINE = re.compile(rb'\[EXIT: ([0-9]+)\] after ~[0-9]+(?:\.[0-9]+)? ?s\n')
RESOURCE_LINE = re.compile(
    rb'\[RUN_SAFE_RESOURCE\] schema=run_safe_resource_v1 outcome=exit reason=exit '
    rb'exit_code=([0-9]+)(?: [a-zA-Z0-9_]+=[a-zA-Z0-9_.,:-]+)+\n'
)


def safe_footer(raw, expected_code):
    """Require unique, adjacent, final run_safe exit and resource records."""
    lines = raw.splitlines(keepends=True)
    exit_indexes = [i for i, line in enumerate(lines) if line.startswith(b'[EXIT: ')]
    resource_indexes = [i for i, line in enumerate(lines) if line.startswith(b'[RUN_SAFE_RESOURCE] ')]
    assert len(exit_indexes) == 1, 'run_safe must emit exactly one exit record'
    assert len(resource_indexes) == 1, 'run_safe must emit exactly one resource record'
    assert exit_indexes[0] == len(lines) - 2, 'exit record must be penultimate line'
    assert resource_indexes[0] == len(lines) - 1, 'resource record must be final line'
    assert resource_indexes[0] == exit_indexes[0] + 1, 'run_safe records must be adjacent'
    exit_match = EXIT_LINE.fullmatch(lines[-2])
    resource_match = RESOURCE_LINE.fullmatch(lines[-1])
    assert exit_match is not None, 'malformed run_safe exit record'
    assert resource_match is not None, 'malformed run_safe resource record'
    assert int(exit_match.group(1)) == expected_code, 'run_safe exit record has wrong status'
    assert int(resource_match.group(1)) == expected_code, 'run_safe resource record has wrong status'
    return lines[-2] + lines[-1]


def check_status(actual, expected, label):
    if actual != expected:
        raise RuntimeError(f'{label}: expected process status {expected}, got {actual}')


def first_error(raw):
    for line in raw.decode(errors='replace').splitlines():
        if re.match(r'^\s*error:\s*instantiating\b', line, re.I):
            continue
        if re.search(r'\bwhile requiring\b', line, re.I):
            continue
        if re.match(r'^\s*error:', line, re.I):
            return line
    return ''


def is_parser_error(line):
    return re.search(r'syntax error|unexpected token|expecting token|unterminated|unclosed|invalid syntax|internal compiler error', line, re.I) is not None


def compile_case(stage, host, name, work):
    fixture = FIXTURES / (name + '.cr')
    binary = work / (stage + '.' + name + '.program')
    cache = work / (stage + '.' + name + '.cache')
    if binary.exists():
        binary.unlink()
    cache.mkdir()
    env = os.environ.copy()
    env.update(CRYSTAL_CACHE_DIR=str(cache))
    if stage == 'original':
        args = ['build', '--no-debug', '--error-trace', '--prelude=empty']
        if sys.platform == 'darwin':
            args.append('--link-flags=-fuse-ld=/usr/bin/ld')
        args += [str(fixture), '-o', str(binary)]
    else:
        env['ADAMAS_LLVM_CACHE'] = '0'
        args = [str(fixture), '--no-prelude', '--no-debug', '--no-ast-cache', '--no-llvm-cache', '-o', str(binary)]
    result = subprocess.run([str(SAFE), str(host), '120', '4096', *args], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=145)
    log = work / (stage + '.' + name + '.compile.log')
    log.write_bytes(result.stdout)
    shutil.rmtree(cache)
    return binary, result, log


def require_rejection(stage, host, name, work):
    reject = (FIXTURES / (name + '.reject')).read_text().strip()
    binary, result, log = compile_case(stage, host, name, work)
    raw = log.read_bytes()
    check_status(result.returncode, 1, f'{stage}:{name}')
    if binary.exists():
        raise RuntimeError(f'{stage}:{name}: rejected compilation left an output binary')
    safe_footer(raw, 1)
    error = first_error(raw)
    if not error or is_parser_error(error) or not re.search(reject, error, re.I):
        raise RuntimeError(f'{stage}:{name}: primary diagnostic mismatch: {error!r}')
    print(f'PASS[{stage}:{name}]', flush=True)


def require_positive(stage, host, name, work):
    binary, result, log = compile_case(stage, host, name, work)
    check_status(result.returncode, 0, f'{stage}:{name} compile')
    if not binary.is_file():
        raise RuntimeError(f'{stage}:{name}: successful compilation produced no binary\n{log.read_text(errors="replace")[-3000:]}')
    safe_footer(log.read_bytes(), 0)
    env = os.environ.copy()
    env['RUN_SAFE_PASSTHROUGH_STDIO'] = '1'
    result = subprocess.run([str(SAFE), str(binary), '5', '512'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    (work / (stage + '.' + name + '.stdout')).write_bytes(result.stdout)
    (work / (stage + '.' + name + '.stderr')).write_bytes(result.stderr)
    expected = (FIXTURES / (name + '.expected')).read_bytes()
    check_status(result.returncode, 0, f'{stage}:{name} runtime')
    exact_footer = safe_footer(result.stderr, 0)
    if result.stderr != exact_footer:
        raise RuntimeError(f'{stage}:{name}: runtime stderr contains output beyond the two run_safe records: {result.stderr!r}')
    if result.stdout != expected:
        raise RuntimeError(f'{stage}:{name}: stdout mismatch {result.stdout!r}, expected {expected!r}')
    binary.unlink()
    print(f'PASS[{stage}:{name}] stdout={result.stdout!r}', flush=True)




POSITIVE = ['same_file_control', 'declare_before_require', 'declare_in_begin_before_require', 'dependency_declares_before_own_require', 'runtime_require_order', 'duplicate_require_once', 'cycle_require_once', 'nested_begin_require_order', 'plain_begin_local_scope', 'declared_top_level_parent_control', 'same_superclass_reopen', 'generic_prior_parent', 'alias_prior_parent', 'method_body_forward_reference', 'class_nested_parent_before_qualified_child', 'class_nested_parent_before_module_child', 'module_nested_parent_before_qualified_child', 'class_parent_before_module_child', 'macro_for_qualified_child_after_require', 'alias_prior_parent_inherited_behavior', 'generic_parent_exact_reopen', 'alias_nested_class_and_module_parent_inherited_behavior']
NEGATIVE = ['require_before_declare_rejected', 'missing_qualified_parent_rejected', 'future_top_level_parent_rejected', 'future_same_file_parent_rejected', 'different_registered_super_reopen_rejected', 'future_parent_reopen_rejected', 'future_generic_parent_rejected', 'class_child_before_later_module_parent', 'module_child_before_later_class_parent']


def collect_stage(stage, host, work):
    failures = []
    for kind, names in [('positive', POSITIVE), ('negative', NEGATIVE)]:
        for name in names:
            try:
                (require_positive if kind == 'positive' else require_rejection)(stage, host, name, work)
            except Exception as exc:
                failures.append(name + ': ' + str(exc))
                print('FAIL[' + stage + ':' + name + '] ' + str(exc), flush=True)
    if failures:
        raise RuntimeError(stage + ' stage failed: ' + repr(failures))
    print(stage.upper() + '_PASS_COMPLETE positives=' + str(len(POSITIVE)) + ' negatives=' + str(len(NEGATIVE)), flush=True)


def main():
    candidate = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT / 'bin/adamas'
    assert len(sys.argv) <= 2, 'usage: run_original_first.py [candidate-host]'
    assert SAFE.is_file() and PINNED.is_file() and candidate.is_file()
    assert set(p.stem for p in FIXTURES.glob('*.cr')) == set(POSITIVE + NEGATIVE)
    work = Path(tempfile.mkdtemp(prefix='adamas_source_declaration_order_'))
    passed = False
    try:
        if not os.environ.get('CRYSTAL_PATH'):
            result = subprocess.run([str(SAFE), str(PINNED), '10', '1024', 'env', 'CRYSTAL_PATH'], env={**os.environ, 'RUN_SAFE_PASSTHROUGH_STDIO': '1'}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
            check_status(result.returncode, 0, 'original CRYSTAL_PATH')
            exact_footer = safe_footer(result.stderr, 0)
            assert result.stderr == exact_footer
            os.environ['CRYSTAL_PATH'] = result.stdout.decode().strip()
        collect_stage('original', PINNED, work)
        collect_stage('candidate', candidate, work)
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


if __name__ == '__main__':
    main()
