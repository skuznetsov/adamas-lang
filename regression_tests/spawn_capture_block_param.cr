# Regression (known-red): spawn closure captures block param / method arg
# by reference to a slot that is shared across yield invocations (or dies
# with the spawning method's stack frame). Original Crystal gives fresh
# 0,1,2,3 values to each spawn.
#
# This is the remaining bug behind Part 6 of examples/bench_comprehensive.cr
# (Fibers total=799980000 expected). The Channel(Int64) tuple-alignment
# half of the bug was fixed by a781fd70; this file tracks what remains.

# Probe A: `.times do |i| spawn { send(i) }` — block param capture.
ch_a = Channel(Int64).new
4.times do |i|
  spawn { ch_a.send(i.to_i64) }
end
sum_a = 0_i64
pk = 0
while pk < 4
  sum_a += ch_a.receive
  pk += 1
end
# Original Crystal: 0+1+2+3 = 6. V2 today: 4+4+4+4 = 16.
if sum_a == 6_i64
  puts "probe_block_param_ok"
else
  puts "probe_block_param_FAIL sum=#{sum_a}"
end

# Probe B: helper method arg capture.
def send_id(ch : Channel(Int64), v : Int32)
  spawn { ch.send(v.to_i64) }
end

ch_b = Channel(Int64).new
4.times do |i|
  send_id(ch_b, i)
end
sum_b = 0_i64
pk2 = 0
while pk2 < 4
  sum_b += ch_b.receive
  pk2 += 1
end
# Original Crystal: 0+1+2+3 = 6. V2 today: 3+3+3+3 = 12.
if sum_b == 6_i64
  puts "probe_helper_arg_ok"
else
  puts "probe_helper_arg_FAIL sum=#{sum_b}"
end
