#!/bin/bash
# Summarize LayoutDecision sidecar TSV (see src/compiler/layout_probe.cr).
#
# Usage:
#   ADAMAS_LAYOUT_PROBE=1 ADAMAS_LAYOUT_PROBE_FILE=/tmp/probe.tsv bin/adamas foo.cr
#   scripts/layout_probe_report.sh /tmp/probe.tsv
set -euo pipefail
f="${1:?usage: layout_probe_report.sh probe.tsv}"

echo "== rows: $(wc -l < "$f" | tr -d ' ')"
echo
echo "== storage kind by phase/context =="
cut -f1,3,7 "$f" | sort | uniq -c | sort -rn
echo
echo "== MIXED-representation types (divergence candidates) =="
awk -F'\t' '
{
  t = $5; k = $7
  kinds[t] = kinds[t] "," k
  detail[t] = detail[t] "\n    " $1 ":" $2 ":" $3 " -> " k " slot=" $8 " access=" $9 \
    ($10 != "" ? " declared=" $10 : "") ($11 != "" ? " effective=" $11 : "")
}
END {
  for (t in kinds) {
    has_inline = (kinds[t] ~ /InlineBytes|BorrowedAddress/)
    has_carrier = (kinds[t] ~ /PointerCarrier/)
    has_ref = (kinds[t] ~ /PointerReference/)
    if ((has_inline && has_carrier) || (has_inline && has_ref) || (has_carrier && has_ref))
      printf "  %s%s\n\n", t, detail[t]
  }
}' "$f"
echo
echo "== slot/access size mismatches =="
awk -F'\t' '$8 != -1 && $9 != -1 && $8 != $9 { print "  " $5 ": " $1 ":" $2 " slot=" $8 " access=" $9 " (" $7 ")" }' "$f" | sort -u
