# Exact generated-runtime probe for HIR::Module's
# Hash(String, Adamas::HIR::Function) registry.  Re-created equal names must
# return the canonical Function and must never append duplicate rows.

require "../../src/compiler/hir/hir"

hir = Adamas::HIR::Module.new("registry-probe")

i = 0
while i < 768
  name = "ProbeOwner#method$#{i}"
  hir.create_function(name, Adamas::HIR::TypeRef::VOID)
  i += 1
end

raise "wrong initial function count: #{hir.function_count}" unless hir.function_count == 768

i = 0
while i < 768
  query = "ProbeOwner#method$#{i}"
  first = hir.function_by_name(query)
  second = hir.create_function(query, Adamas::HIR::TypeRef::VOID)
  raise "registry miss for #{query}" unless first && first.same?(second)
  i += 1
end

raise "duplicate function rows: #{hir.function_count}" unless hir.function_count == 768

i = 0
while i < 768
  if i % 2 == 0
    name = "ProbeOwner#method$#{i}"
    raise "remove failed for #{name}" unless hir.remove_function(name)
  end
  i += 1
end

raise "stale rows after remove: #{hir.function_count}" unless hir.function_count == 384

i = 0
while i < 768
  if i % 2 == 0
    name = "ProbeOwner#method$#{i}"
    hir.create_function(name, Adamas::HIR::TypeRef::VOID)
  end
  i += 1
end

raise "wrong count after re-add: #{hir.function_count}" unless hir.function_count == 768
puts "hir-function-registry-ok"
