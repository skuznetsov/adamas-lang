@[Link("c")]
lib OutScopeRepeatedBlockProbe
  fun time(value : Int64*) : Int64
end

def run_scope_block(&block : ->)
  yield
end

run_scope_block do
  OutScopeRepeatedBlockProbe.time(out block_end)
  OutScopeRepeatedBlockProbe.time(out block_end)
end
