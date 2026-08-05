def snapshot_like(
  caller_locals : Hash(String, Int32),
  callee_locals : Set(String)?,
) : Hash(String, Int32)
  snapshot = caller_locals.dup
  caller_locals.each_key do |name|
    next if callee_locals && callee_locals.includes?(name)
    snapshot[name] = 1
  end
  snapshot
end

def snapshot_with_argument_mutation(
  caller_locals : Hash(String, Int32),
  callee_locals : Set(String)?,
) : Hash(String, Int32)
  snapshot = caller_locals.dup
  caller_locals.each_key do |name|
    next if callee_locals && callee_locals.includes?(begin
              callee_locals = nil
              name
            end)
    snapshot[name] = 1
  end
  snapshot
end

puts snapshot_like({"keep" => 0}, Set{"skip"})["keep"]
puts snapshot_with_argument_mutation({"keep" => 0}, Set{"skip"})["keep"]
