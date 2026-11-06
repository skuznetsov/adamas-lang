# Open alias-visibility counterexamples

These unchanged no-prelude sources are stock-qualified on Crystal 1.22.1
(35q3284). Baseline S1 35q3233 and candidate S1 35q3269 fail both identically
(35q3286/35q3285). They are separate obligations, not passing candidate tests.

- An inherited alias named String must retain its Int32 type while ::String
  remains global. Both Adamas builds infer String for the inherited result.
- Orphan from an unrelated module is not visible as a bare annotation in
  PlainContext. Stock rejects undefined constant Orphan; both Adamas builds
  incorrectly accept it.

expectations.json retains source hashes and original outputs/diagnostics.
Do not change these expectations or remove restrictions to count them as
passes. The main inherited type precedence runner covers the narrower early
lookup repair; annotation qualification and suffix visibility remain open.
