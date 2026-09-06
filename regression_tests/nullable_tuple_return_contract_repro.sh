#!/usr/bin/env bash
# Completed tuple return layouts must survive later AST-only inference.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${1:?usage: $0 COMPILER}"
work="$(mktemp -d "${TMPDIR:-/tmp}/nullable-tuple-return.XXXXXX")"
trap 'rm -rf "$work"' EXIT
for order in nil_first value_first annotated; do
  case "$order" in
    nil_first) body='return {vars, nil} unless flag
    {vars, Expr.new(73)}'; annotation='' ;;
    value_first) body='return {vars, Expr.new(73)} if flag
    {vars, nil}'; annotation='' ;;
    annotated) body='return {vars, nil} unless flag
    {vars, Expr.new(73)}'; annotation=' : Tuple(Array(String), Expr | Nil)' ;;
  esac
  cat > "$work/$order.cr" <<CR
lib LibC
  fun exit(status : Int32) : NoReturn
end
struct Expr
  getter value : Int32
  def initialize(@value : Int32)
  end
end
class Parser
  def header(flag : Bool)$annotation
    vars = ["property"]
    $body
  end
  def run(flag : Bool, enter : Bool)
    vars = nil
    iterable = nil
    if enter
      vars, iterable = header(flag)
    end
    iterable ? iterable.value : 0
  end
end
parser = Parser.new
LibC.exit(11) unless parser.run(true, true) == 73
LibC.exit(12) unless parser.run(false, true) == 0
LibC.exit(13) unless parser.run(true, false) == 0
LibC.exit(14) unless parser.run(true, true) == 73
LibC.exit(0)
CR
  if ! "$root/scripts/run_safe.sh" "$compiler" 90 8192 "$work/$order.cr" --no-prelude -o "$work/$order" > "$work/$order.log" 2>&1; then
    cat "$work/$order.log"
    exit 1
  fi
  if ! "$root/scripts/run_safe.sh" "$work/$order" 5 512 >> "$work/$order.log" 2>&1; then
    cat "$work/$order.log"
    exit 1
  fi
  echo "PASS[$order]"
done
