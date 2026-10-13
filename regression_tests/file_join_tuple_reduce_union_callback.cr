# EXPECT: OK join=./bb.cr
#
# Regression: `File.join` forwards its splat tuple to `Path#join(parts : Enumerable)`,
# which folds the tuple with `Tuple#reduce(memo, &)` — an anonymous-block raw yield.
# The tuple elements are a `Path | String` union, so the callback must receive the
# union by value. Without a registered raw-callback ABI contract the yield site fell
# back to the legacy payload-pointer ABI while the materialized block proc still took
# the full union: the callee read the payload pointer as the union tag and aborted
# inside `Path#join(part)` (this blocked the stage2 -> stage3 bootstrap).
three = File.join("a", "b", "c")
puts "OK join3=#{three}"
joined = File.join(".", "bb.cr")
puts "OK join=#{joined}"
# Trailing sentinel: the EXPECT marker must not be the last stdio write, so a
# truncated final flush cannot masquerade as a regression.
puts "DONE"
