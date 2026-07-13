require "../../../src/compiler/hir/hir"
require "../../../src/compiler/hir/escape_analysis"

hir = Adamas::HIR::Module.new("method-effect-provider-probe")
summary = Adamas::HIR::MethodEffectSummary.new(transfer: true)
hir.add_method_effect("Box#put", summary)

value_type = hir.intern_type(
  Adamas::HIR::TypeDescriptor.new(Adamas::HIR::TypeKind::Class, "Payload")
)
function = hir.create_function("probe", Adamas::HIR::TypeRef::VOID)
payload = Adamas::HIR::Allocate.new(function.next_value_id, value_type)
function.get_block(function.entry_block).add(payload)

call = Adamas::HIR::Call.new(function.next_value_id, Adamas::HIR::TypeRef::VOID, "")
call.configure_without_receiver("Box#put", [payload.id])
function.get_block(function.entry_block).add(call)
function.get_block(function.entry_block).terminator = Adamas::HIR::Return.new

Adamas::HIR::EscapeAnalyzer.new(function, nil, hir).analyze
raise "method effect provider did not transfer the argument" unless payload.lifetime == Adamas::HIR::LifetimeTag::ArgEscape

puts "generated-method-effect-provider-ok"
