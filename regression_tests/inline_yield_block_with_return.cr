# Regression test: non-local return in block must propagate through nested
# inline yield. Pattern mirrors stdlib Array#fetch -> check_index_out_of_bounds.
#
# Before fix: when inline_yield_function bailed (e.g. block_arena_mismatch),
# it fell through to lower_block_to_proc which lost the non-local return.
# Result was the wrong value (the success branch's index, e.g. 20 instead of 120).
#
# After fix: the six bail-out sites in inline_yield_function gate fallback on
# fallback_allowed (= !block_contains_return). When the block has a return,
# inline_yield_function force-inlines despite arena/receiver issues, preserving
# non-local return semantics.
# EXPECT: fetch_return_ok

class Foo
  def initialize(@n : Int32)
  end

  def size
    @n
  end

  def unsafe_fetch(index : Int32)
    index * 100
  end

  def fetch(index : Int32, &)
    index = check_oob(index) do
      return yield index
    end
    unsafe_fetch(index)
  end

  private def check_oob(index, &)
    if 0 <= index < size
      index
    else
      yield
    end
  end
end

# index 20 is out-of-bounds for size 10, so the block fires.
# `return yield index` means: yield to outer, then non-local return from fetch.
# Outer block `{ |i| i + 100 }` returns 20 + 100 = 120.
# fetch returns 120 (the yielded value), not unsafe_fetch's 20*100=2000.
result = Foo.new(10).fetch(20) { |i| i + 100 }
unless result == 120
  puts "FAIL: expected 120, got #{result}"
  exit 1
end

# In-bounds case: block does not fire, unsafe_fetch returns index*100.
inb = Foo.new(10).fetch(5) { |i| i + 100 }
unless inb == 500
  puts "FAIL: expected 500, got #{inb}"
  exit 1
end

puts "fetch_return_ok"
