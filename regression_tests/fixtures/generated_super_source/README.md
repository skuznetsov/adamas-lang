# Generated super source binding fixtures

The regression script qualifies exact source binding, lexical namespaces,
concrete generic module applications, source include order, and preservation of
argument rejection. It does not qualify every source-result or value-kind path.

`actual_return_pending.cr` is an open negative falsifier: Crystal 1.22.1 rejects
the actual String return against Int32, while both committed baseline 61ecbf0f
and the isolated owner-only patch accept it (35q229 / 35q228). The separate
source-result-contract WIP rejects it (35q206 / 35q216). Keep that stricter
requirement; exact Def/arena ownership alone does not establish return checking.
This fixture must become a required rejection gate with that contract slice.

Runtime `self` and lexical signature ownership are separate. Required positives
cover nullable enum self, Tuple(self, Result) with a conflicting caller Result
alias, and two enum receivers consecutively to detect cache contamination.

`class_nullable_self_pending.cr` is an open positive falsifier: stock Crystal
prints AA, while both the committed baseline and this fix reject the generated
child super body as returning the base class (35q253 / 35q252). This is a
pre-existing inherited class-method runtime receiver defect. It is excluded
from the passing loop and remains required work, not a relaxed expectation.
