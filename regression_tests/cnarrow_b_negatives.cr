# C-narrow-b NEGATIVE coverage reducer (GPT blocker 3): the carrier-required shapes the
# first preflight reducer did not cover. NONE of these V3 loads may be `eligible`.
#   direct arr[i]=        -> intervening_mutation
#   alias b[i]= (b = arr) -> intervening_mutation (no MIR Copy; b reuses arr's value-id)
#   delete_at / shift / insert -> intervening_call (Array mutation lowers to a Call)
#   cross-block use       -> cross_block
# Compile-only (the preflight is a read-only census; the post-mutation field reads are
# deliberately stale and would be UB at runtime — never executed by the reducer).
struct V3
  getter a : Int32
  getter b : Int32
  getter c : Int32

  def initialize(@a : Int32, @b : Int32, @c : Int32)
  end
end

arr = [] of V3
i = 0
while i < 16
  arr << V3.new(i, i, i)
  i += 1
end
pb = V3.new(1, 1, 1)

# direct arr[i]= between load and field use.
v1 = arr[0]
arr[1] = pb
a1 = v1.a

# alias b[i]= (b = arr).
b = arr
v2 = arr[2]
b[3] = pb
a2 = v2.a

# delete_at between load and use.
v3 = arr[0]
arr.delete_at(4)
a3 = v3.a

# shift between load and use.
v4 = arr[0]
arr.shift
a4 = v4.a

# insert between load and use.
v5 = arr[0]
arr.insert(1, pb)
a5 = v5.a

# cross-block use: load in the entry block, field read in a successor block.
v6 = arr[0]
a6 = 0
if arr.size > 100
  a6 = v6.a
end

STDERR.puts "a1=#{a1} a2=#{a2} a3=#{a3} a4=#{a4} a5=#{a5} a6=#{a6}"
STDOUT.flush
exit(0)
