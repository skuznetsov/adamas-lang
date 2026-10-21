@[Link("c")]
lib OutScopeConditionProbe
  fun time(value : Int64*) : Int64
end

if OutScopeConditionProbe.time(out condition_end) != 0_i64
  condition_end
else
  condition_end
end
