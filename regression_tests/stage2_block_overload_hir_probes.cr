# HIR probes for block overload resolution (typed vs arity-only) and multi-arg + block.
# Oracle script greps the emitted HIR for stable mangled call targets.
#
# inline_yield_fallback_call (unsafe yield inline → emitted Call with proc) uses the same
# typed-first + arity-only-uniqueness gate as emit/repair/canonicalization. A dedicated
# E2E reducer that forces that path while keeping two same-arity typed block overloads is
# not included: it depends on callee yield+return skipping inline, a bare inline_key, and
# environment flags — too brittle to pin as a stable regression; the guard matches other sites.

class BlockOverloadTypedProbe
  def m(x : Int32, &)
    x
  end

  def m(x : String, &)
    x.bytesize
  end
end

class TwoArgBlockProbe
  def m(x : Int32, &)
    1
  end

  def m(x : Int32, y : Int32, &)
    2
  end
end

a = BlockOverloadTypedProbe.new.m(1) { 0 }
b = TwoArgBlockProbe.new.m(3, 4) { 0 }
puts a
puts b
