# Open unsigned enum payload obligation

This frozen source must print `C` followed by a newline. Stock Crystal 1.22.1
passes (35q3254). The pre-fix compiler prints `I` (35q3259); the enum value
source-result candidate selects the UInt64 overload but prints `X` (35q3255).
Its LLVM main already passes zero as the enum member, before `Enum#value`.
The metadata/parser stores enum values as Int64 and silently leaves the first
member at zero when this explicit UInt64 value does not fit. Preserve the full
declared integer domain and reject invalid explicit values instead of silently
substituting an ordinal. No stdlib change is authorized.

This is excluded from the bounded six-positive/one-negative source-result gate;
it is a confirmed counterexample to general unsigned payload parity. Run stock
first, then the candidate, through scripts/run_safe.sh with --prelude=empty /
--no-prelude. The manifest paths are relative to this directory. Refresh after
enum parsing, metadata representation, constant evaluation or value lowering.
