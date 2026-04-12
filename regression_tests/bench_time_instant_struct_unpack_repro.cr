# Compiler: struct sequential multi-assign (forked Event#initialize pattern).
# EXPECT: unpack_ok
s, n = Crystal::System::Time.instant
puts s
puts n
puts "unpack_ok"
