# L11 regression (2026-07-07, session-13): a yield-passthrough wrapper whose
# callsites reach the inline-yield fallback (proc-materialized) path must get
# a PER-BLOCK-RETURN-SHAPE `_block` function, not one shared symbol.
# Historical failure: the ONE shared `with_map$$Int32_block` return/proc ABI
# was stamped by a single callsite's block return type; every other-typed
# callsite raw-reinterpreted the result. In-vivo (s2): shared
# `with_type_param_map$$Hash(String,String)_block` accreted
# `TypeRef | Array(TypeRef)` (no Nil) over 41 callsites and called the block
# proc as `call void %_()` returning zeroinitializer -> the nilable callsite
# read a non-nil tag with null payload -> null TypeRef ->
# specialize_type_with_receiver_map segfault.
# Triple nesting exceeds INLINE_YIELD_MAX_REPEAT=2, forcing the innermost
# callsite onto the fallback path. Blocks capture locals (proc-materialized)
# and return three DIFFERENT types: Array(Box), Box, Nil | Box (nil taken).
# EXPECT: block_shape_ok

struct Box
  def initialize(@v : Int32)
  end

  def v : Int32
    @v
  end
end

class Ctx
  @depth = 0

  def with_map(m : Int32, &)
    old = @depth
    @depth = m
    begin
      yield
    ensure
      @depth = old
    end
  end
end

def truthy(n : Int32) : Bool
  n > 2
end

ctx = Ctx.new

# fallback callsite 1: innermost block returns Array(Box)
arr = [Box.new(1)]
r1 = ctx.with_map(1) do
  ctx.with_map(2) do
    ctx.with_map(3) do
      arr
    end
  end
end

# fallback callsite 2: innermost block returns Box
seed = 5
r2 = ctx.with_map(4) do
  ctx.with_map(5) do
    ctx.with_map(6) do
      Box.new(seed)
    end
  end
end

# fallback callsite 3: innermost block returns Nil | Box, nil path at runtime
n = 1
r3 = ctx.with_map(7) do
  ctx.with_map(8) do
    ctx.with_map(9) do
      truthy(n) ? Box.new(n) : nil
    end
  end
end

# non-nil path of the nilable shape
n2 = 7
r4 = ctx.with_map(10) do
  ctx.with_map(11) do
    ctx.with_map(12) do
      truthy(n2) ? Box.new(n2) : nil
    end
  end
end

if r3.nil? && (got = r4) && got.v == 7 && r1.size == 1 && r2.v == 5
  puts "block_shape_ok"
else
  puts "block_shape_MISMATCH r1=#{r1.size} r2=#{r2.v} r3_nil=#{r3.nil?} r4=#{r4 ? "set" : "nil"}"
end
