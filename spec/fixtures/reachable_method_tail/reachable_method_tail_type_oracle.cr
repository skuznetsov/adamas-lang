require "./reachable_method_tail"

# Original-Crystal source contract for the return-type cases checked directly
# by reachable_method_tail_spec.cr against the candidate HIR lowering.
puts typeof(ReachableTailModule.explicit_terminal) == Int32
puts typeof(ReachableTailClass.new.explicit_terminal) == Int32

puts typeof(ReachableTailModule.all_branches_terminal(true)) == Int32
puts typeof(ReachableTailClass.new.all_branches_terminal(true)) == Int32

puts typeof(ReachableTailModule.nil_tail_after_return(true)) == (Int32 | Nil)
puts typeof(ReachableTailClass.new.nil_tail_after_return(true)) == (Int32 | Nil)

puts typeof(ReachableTailModule.string_tail_after_return(true)) == (Int32 | String)
puts typeof(ReachableTailClass.new.string_tail_after_return(true)) == (Int32 | String)
