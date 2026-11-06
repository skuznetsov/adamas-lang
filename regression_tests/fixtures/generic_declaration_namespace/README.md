# Generic declaration namespace replay

The six original-first main cases cover generic nested field types first
materialized from class-body ivar defaults, nested owner paths, included-module
lexical types and setters, ordinary demand, and an incompatible annotated return.
The two class-body default cases reject with caller-owned Entry types before the
fix. Each template must replay registration in its captured declaration
namespace, including an explicit nil that clears an unrelated caller override.

Three stock-qualified OPEN companions remain excluded from candidate success.
The unrelated constructor-argument negative exposes this separate obligation:
the baseline accepts Other::Entry where Box::Entry is required. It is excluded
from candidate success and is a separate allocator/admission obligation.
Two rooted generic reopenings also fail before and after this fix, reporting
Pointer instead of Int32 at the outer method result.

The generic-reopening neighboring gate has a separate pre-existing failure for
ReopeningBareBox(::String). That failure occurs before and after this fix;
the remaining nine cases pass in lazy and eager modes. This bounded gate does
not establish whole-prelude, bootstrap or LavinMQ runtime/test parity.
