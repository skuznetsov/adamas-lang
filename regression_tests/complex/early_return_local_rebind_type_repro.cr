# Path-sensitive local rebinding regression. The assignment in the terminating
# branch must not contaminate the type of the same source-level local on the
# fallthrough path.

def early_return_local_rebind(flag : Bool) : Bool
  if flag
    values = Set(UInt32).new
    values << 1_u32
    return values.includes?(1_u32)
  end

  values = [] of UInt32
  values << 2_u32
  contains = ->(value : UInt32) { values.includes?(value) }
  contains.call(2_u32)
end

raise "true branch failed" unless early_return_local_rebind(true)
raise "fallthrough branch failed" unless early_return_local_rebind(false)
puts "early-return-local-rebind-ok"
