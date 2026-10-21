@[Link("c")]
lib OutScopeBlockEscapeProbe
  fun time(value : Int64*) : Int64
end

def run_scope_block(&block : ->)
  yield
end

run_scope_block do
  OutScopeBlockEscapeProbe.time(out local_end)
end

OutScopeBlockEscapeProbe.time(out local_end)
