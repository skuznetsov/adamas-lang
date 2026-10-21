@[Link("c")]
lib OutScopeSiblingBlockProbe
  fun time(value : Int64*) : Int64
end

def run_scope_block(&block : ->)
  yield
end

run_scope_block do
  OutScopeSiblingBlockProbe.time(out block_end)
end

run_scope_block do
  OutScopeSiblingBlockProbe.time(out block_end)
end
