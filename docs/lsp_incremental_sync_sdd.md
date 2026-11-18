# LSP incremental document synchronization frontier

Status: locally verified on 2026-09-20.

## Problem and factual anchor

Adamas accepts ranged `textDocument/didChange` notifications but advertises
`textDocumentSync = 1` (full synchronization). A conforming editor must
therefore materialize and JSON-serialize the complete document for every
ordinary edit. On the current 5,494,646-byte `ast_to_hir.cr` input, that puts a
multi-megabyte copy on the editor input path even when the edit itself is one
character.

Before this slice, the ranged-change consumer was not safe to advertise: its
incoming position conversion counted Unicode scalar values, while LSP
positions use UTF-16 code units. It also included line terminators in
out-of-range clamping. Advertising incremental synchronization before fixing
those boundaries could corrupt text around non-BMP characters or CRLF lines.

## Admitted behavior

- Advertise incremental document synchronization only after incoming LSP
  ranges are converted from UTF-16 code units to UTF-8 byte offsets.
- Apply every change in a `contentChanges` array against the snapshot produced
  by the preceding change, as required by LSP ordering.
- Preserve full-document changes without a `range` for compatibility.
- Ignore malformed or out-of-document ranges instead of interpreting them as
  whole-document replacements.
- Clamp invalid columns to the content portion of the requested line, before
  either `LF` or `CRLF` terminators, without splitting a UTF-8 scalar value.

## Rejected claims and deferred work

- This does not make parsing, semantic analysis, token production, or the
  server-side immutable string splice incremental.
- This does not promise a portable key-to-render latency threshold.
- This does not permit ranged edits to be advertised while any known UTF-16,
  CRLF, or sequential-change counterexample fails.
- Incremental parsing and a piece-table/rope document store are separate
  frontiers. This slice only removes the avoidable full-document transport from
  ordinary edits.

## Risk and rollback

Risk is CAUTION: incorrect coordinate conversion silently changes source text
and can poison every subsequent LSP result. Rollback is the single isolated
commit on `codex/lsp-incremental-sync`; the user's active Adamas worktree is not
modified.

The strongest failure mode is an astral Unicode character shifting a later
range by one code unit and consuming a line terminator. Guards therefore cover
non-BMP UTF-16 positions, CRLF preservation, multiple ordered changes, the
existing ASCII range path, and the range-less full-sync fallback.

## Falsifiers and Definition of Done

1. Before production changes, focused specs must fail for the advertised sync
   kind and for UTF-16/CRLF/sequential ranged edits.
2. After the change, that focused pack must pass through `scripts/run_safe.sh`.
3. The complete LSP spec suite must pass through the same safety wrapper.
4. `src/lsp_main.cr` must build, Crystal formatting and `git diff --check` must
   pass, and an adversarial review must find no affected inbound coordinate
   consumer that still assumes Unicode scalar columns.
5. Completion claims remain scoped to wire transport and coordinate fidelity;
   server analysis latency and end-to-end terminal latency remain open.

## Implemented boundary and evidence

`ServerCapabilities` now advertises incremental synchronization. Incoming
ranges reuse the document state's line-offset table and convert UTF-16 columns
to UTF-8 byte offsets without including `LF` or `CRLF` terminators. Multiple
changes rebuild that table only between snapshots; the common one-change
notification reuses the existing table. Range-less changes retain the original
full-document behavior.

The pre-change focused binary produced three discriminating failures: sync kind
`1`, corrupted emoji/CRLF output (`"😀 = 19\n"`), and a sequential edit that
consumed the final newline. The completed slice passed:

- `regression_tests/lsp_incremental_sync_repro.sh`: 12 examples;
- the complete `spec/lsp/*_spec.cr` binary through `scripts/run_safe.sh`: 271
  examples;
- the focused signature-help pack: 16 examples, including an astral-character
  guard for internally derived UTF-16 positions;
- Adamantine's sync-capability/materialization bridge specs: 55 examples;
- `crystal build src/lsp_main.cr`, Crystal formatting, shell syntax validation,
  and `git diff --check`.

This evidence decays if LSP coordinate conversion, document state line offsets,
`didChange` ordering, or the advertised synchronization capability changes.
