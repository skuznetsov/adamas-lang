# Source return discard contract

Run the matching regression script with an Adamas compiler path. Original Crystal runs every case first; compilation and native executables use run_safe.sh. Positive output is compared byte-for-byte. Negative results require the specific source return or Proc argument diagnostic, compiler exit 1, and no emitted executable. Crashes, parser errors and backend failures do not qualify as semantic rejection.

The nine positives cover explicit and implicit Nil returns, source Nil for a Void ABI, branch effect order, instance/module/static/bare calls, aliases, call-local forall bindings, and an all-terminal NoReturn body. The two negatives preserve the distinction between Nil and Nil.class and reject an ordinary incompatible Int32 return.

Scope: direct, exact source result discard. Virtual target-family certification, full prelude, bootstrap, and LavinMQ runtime/upstream parity remain separate obligations.
