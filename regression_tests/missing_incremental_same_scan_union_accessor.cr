require "../src/compiler/hir/ast_to_hir"
require "../src/compiler/frontend/lexer"
require "../src/compiler/frontend/parser"

class Adamas::HIR::AstToHir
  def __probe_function_def_names(base_name : String) : Array(String)
    @function_defs.keys.select do |name|
      name == base_name || name.starts_with?("#{base_name}$")
    end
  end

  def __probe_lower_missing_call_targets : Nil
    lower_missing_call_targets
  end
end

source = <<-CRYSTAL
  def force_second_scan : Int32
    1
  end

  class Outer
    class Info
      property kind : FileType
    end
  end

  enum FileType
    Other
    Tuple
  end
CRYSTAL

lexer = Adamas::Compiler::Frontend::Lexer.new(source)
parser = Adamas::Compiler::Frontend::Parser.new(lexer)
result = parser.parse_program
arena = result.arena
roots = result.roots
converter = Adamas::HIR::AstToHir.new(
  arena,
  sources_by_arena: {arena.object_id.to_u64 => source},
)
converter.arena = arena

function_def = roots.compact_map do |expr_id|
  arena[expr_id].as?(Adamas::Compiler::Frontend::DefNode)
end.first
outer_node = roots.compact_map do |expr_id|
  node = arena[expr_id]
  next unless node.is_a?(Adamas::Compiler::Frontend::ClassNode)
  class_node = node.as(Adamas::Compiler::Frontend::ClassNode)
  next unless String.new(class_node.name.not_nil!) == "Outer"
  class_node
end.first
enum_node = roots.compact_map do |expr_id|
  arena[expr_id].as?(Adamas::Compiler::Frontend::EnumNode)
end.first

converter.register_function(function_def)
converter.register_class(outer_node)
converter.register_enum(enum_node)
second_scan_target =
  converter.__probe_function_def_names("force_second_scan").first
getter_target = "Outer::Info#kind"
driver = converter.module.create_function(
  "Owner#same_scan_union_driver",
  Adamas::HIR::TypeRef::VOID,
)
block = driver.get_block(driver.entry_block)
getter_call = Adamas::HIR::Call.new(
  driver.next_value_id,
  Adamas::HIR::TypeRef::VOID,
  getter_target,
)
union_call = Adamas::HIR::Call.new(
  driver.next_value_id,
  Adamas::HIR::TypeRef::VOID,
  "Nil | Outer::Info#kind",
)
order = ENV["ADAMAS_SAME_SCAN_ORDER"]? || "demand_first"
if order == "materializer_first"
  block.add(union_call)
  block.add(getter_call)
else
  block.add(getter_call)
  block.add(union_call)
end
block.add(
  Adamas::HIR::Call.new(
    driver.next_value_id,
    Adamas::HIR::TypeRef::INT32,
    second_scan_target,
  )
)

puts "[SAME_SCAN_ACCESSOR] order=#{order} before_getter_body=#{converter.module.has_function_with_body?(getter_target) ? 1 : 0}"
ENV["ADAMAS_MISSING_INCREMENTAL_FALSIFIER"] = "1"
converter.__probe_lower_missing_call_targets
puts "[SAME_SCAN_ACCESSOR] order=#{order} canonical_getter=#{getter_call.method_name} canonical_union=#{union_call.method_name}"
puts "[SAME_SCAN_ACCESSOR] order=#{order} after_getter_body=#{converter.module.has_function_with_body?(getter_target) ? 1 : 0} second_scan_body=#{converter.module.has_function_with_body?(second_scan_target) ? 1 : 0}"
