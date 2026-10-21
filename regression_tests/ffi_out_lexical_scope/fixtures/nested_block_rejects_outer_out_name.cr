@[Link("c")]
lib OutScopeNestedReuseProbe
  fun time(value : Int64*) : Int64
end

def run_scope_block(&block : ->)
  yield
end

OutScopeNestedReuseProbe.time(out outer_end)
run_scope_block do
  OutScopeNestedReuseProbe.time(out outer_end)
end
