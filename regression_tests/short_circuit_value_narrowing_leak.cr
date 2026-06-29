# Regression: value-expression short-circuit lowering leaked a branch-local
# nilable narrowing beyond the expression. In
#
#   ok = full.nil? || full == method
#   value = full || "nil"
#
# the RHS of the first `||` narrows `full` to a non-nil String while evaluating
# `full == method`. That narrowed binding is only valid inside the RHS branch.
# Before this guard, lower_short_circuit registered it in the surrounding local
# environment, so the later `full || "nil"` read a non-dominating UnionUnwrap.
# The backend correctly dropped that incoming to null; printing `value` then
# crashed in String#bytesize. This is the value-expression sibling of
# short_circuit_condition_narrowing_leak.cr.
# EXPECT:
# VALUE=Exception::CallStack.skip
# RECV_NIL=true
# FMN_OK=false
# NO_BLOCK=true
def probe(flag : Bool)
  method_name = "skip"
  full_method_name : String? = flag ? "Exception::CallStack.skip" : nil
  recv : UInt32? = nil

  post_recv_nil = (recv || 0_u32) == 0_u32
  post_fmn_ok = full_method_name.nil? || full_method_name == method_name
  post_no_block = true

  value = full_method_name || "nil"
  puts "VALUE=#{value}"
  puts "RECV_NIL=#{post_recv_nil}"
  puts "FMN_OK=#{post_fmn_ok}"
  puts "NO_BLOCK=#{post_no_block}"
  STDOUT.flush
end

probe(true)
