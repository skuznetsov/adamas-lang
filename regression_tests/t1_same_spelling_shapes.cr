# T1 falsifier reducer: keep one rendered method spelling while varying the
# receiver, positional argument, block, and named-argument shape.
#
# The guard intentionally does not assert semantic identity success. It checks
# only whether the exact versioned T1 producer record is available on this
# path; a missing record is not proof of global absence or continuity.

class T1Left
  def route(value : Int32) : Int32
    value + 10
  end

  def route(value : String) : Int32
    20
  end
end

class T1Right
  def route(value : Int32) : Int32
    value + 30
  end
end

class T1Block
  def route(value : Int32, &block : Int32 -> Int32) : Int32
    yield value
  end
end

class T1Named
  def route(*, level : Int32) : Int32
    level + 40
  end
end

left = T1Left.new
right = T1Right.new
block_owner = T1Block.new
named_owner = T1Named.new

# Same spelling, distinct receiver/argument families.
r1 = left.route(1)
r2 = left.route("x")
r3 = right.route(1)

# Same spelling, block-bearing and named-only shapes.
r4 = block_owner.route(2) { |v| v + 1 }
r5 = named_owner.route(level: 3)

# Keep the reducer executable when a caller chooses to run it.
exit 2 unless {r1, r2, r3, r4, r5} == {11, 20, 31, 3, 43}
exit 0
