# Regression: Atomic(Int32) atomicrmw ops must stay i32-typed even when Atomic(Bool)
# coexists in the same compilation unit. Before the fix, generic forall-T inference
# dragged the Int32 call site's `Ops.atomicrmw(...) : T` return type to Bool (i1),
# so the atomic result type was i1 while the value operand was i32 -> the byte-round
# path emitted `zext i1 <i32 value>` and llc rejected it
# ("'%value' defined with type 'i32' but expected 'i1'"). Fix: derive the atomicrmw
# result type from the value operand type, not from the (contaminatable) call return.
#
# Covers: Bool byte-round path still correct (regression guard), Int32 rmw family,
# Int64, and swap (which also lowers through the atomicrmw wrapper).

# --- Atomic(Bool): byte-round path must remain correct when Int32 also present ---
b = Atomic(Bool).new(false)
b.set(true)
puts "BOOL_GET #{b.get}"                     # true
old_b = b.swap(false)
puts "BOOL_SWAP old=#{old_b} now=#{b.get}"   # old=true now=false
old_cas_b, _ = b.compare_and_set(false, true)  # returns {old_value, success}
puts "BOOL_CAS #{old_cas_b} now=#{b.get}"    # old=false now=true (CAS succeeded)

# --- Atomic(Int32): the rmw family, in the SAME unit as Atomic(Bool) ---
i = Atomic(Int32).new(5)
puts "INT_ADD #{i.add(5)}"    # returns old = 5
puts "INT_AFTER_ADD #{i.get}" # 10
puts "INT_SUB #{i.sub(3)}"    # returns old = 10
puts "INT_AFTER_SUB #{i.get}" # 7
puts "INT_AND #{i.and(6)}"    # returns old = 7  (7 & 6 = 6)
puts "INT_AFTER_AND #{i.get}" # 6
puts "INT_OR #{i.or(1)}"      # returns old = 6  (6 | 1 = 7)
puts "INT_AFTER_OR #{i.get}"  # 7
puts "INT_XOR #{i.xor(1)}"    # returns old = 7  (7 ^ 1 = 6)
puts "INT_AFTER_XOR #{i.get}" # 6
old_i = i.swap(42)
puts "INT_SWAP old=#{old_i} now=#{i.get}"  # old=6 now=42
old_cas_i, _ = i.compare_and_set(42, 100)  # returns {old_value, success}
puts "INT_CAS #{old_cas_i} now=#{i.get}"   # old=42 now=100 (CAS succeeded)

# --- Atomic(Int64): a wider T alongside Bool + Int32 ---
j = Atomic(Int64).new(1000_i64)
puts "I64_ADD #{j.add(1_i64)}"  # returns old = 1000
puts "I64_AFTER #{j.get}"       # 1001

puts "ALL_OK"
