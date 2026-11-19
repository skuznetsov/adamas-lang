def checked_result(value : Nil) : Int32
  value || unknown_no_flow_rhs
end

checked_result(nil)
