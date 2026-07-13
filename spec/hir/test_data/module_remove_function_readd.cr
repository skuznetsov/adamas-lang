require "../../../src/compiler/hir/hir"

hir = Adamas::HIR::Module.new("generated-registry-probe")

names = Array(String).new(768) do |index|
  String.build { |io| io << "Owner#work$Fn" << index }
end
original = names.map { |name| hir.create_function(name, Adamas::HIR::TypeRef::VOID) }
raise "initial function count mismatch" unless hir.function_count == 768

names.each_with_index do |name, index|
  next if index.odd?
  raise "remove failed for #{name}" unless hir.remove_function(name)
end
raise "retained function count mismatch" unless hir.function_count == 384
base_functions = hir.functions_by_base_name("Owner#work")
raise "retained base-name count mismatch" unless base_functions && base_functions.size == 384

names.each_with_index do |name, index|
  if index.odd?
    retained = hir.function_by_name(name)
    raise "retained identity lost for #{name}" unless retained && retained.same?(original[index])
  else
    raise "stale name index for #{name}" if hir.function_by_name(name)
  end
end

canonical = original.dup
names.each_with_index do |name, index|
  next if index.odd?
  replacement = hir.create_function(name, Adamas::HIR::TypeRef::VOID)
  raise "removed object reused for #{name}" if replacement.same?(original[index])
  canonical[index] = replacement
end
raise "duplicate row after re-add" unless hir.function_count == 768
base_functions = hir.functions_by_base_name("Owner#work")
raise "re-added base-name count mismatch" unless base_functions && base_functions.size == 768

names.each_with_index do |name, index|
  lookup = hir.function_by_name(name)
  raise "non-canonical lookup for #{name}" unless lookup && lookup.same?(canonical[index])
  raise "non-canonical create for #{name}" unless hir.create_function(name, Adamas::HIR::TypeRef::VOID).same?(canonical[index])
end
raise "duplicate rows after canonical creates" unless hir.function_count == 768

puts "generated-hir-function-registry-ok"
