# T1 downstream falsifier reducer: two distinct source calls select the same
# non-inline Foo#bar(Int32) body. The guard is deliberately diagnostic: the
# current ledger has symbol-scoped materialization rows, not per-call terminal
# identity, so a red result is scoped to this compiler/configuration path.

class Foo
  def bar(value : Int32) : Int32
    value + 1
  end
end

foo = Foo.new
first = foo.bar(1)
second = foo.bar(2)

exit 11 unless first == 2
exit 12 unless second == 3
exit 0
