@[Link("c")]
lib OutScopeSiblingBranchProbe
  fun getpid : Int32
  fun time(value : Int64*) : Int64
end

if OutScopeSiblingBranchProbe.getpid > 0_i32
  OutScopeSiblingBranchProbe.time(out branch_end)
else
  OutScopeSiblingBranchProbe.time(out branch_end)
end
