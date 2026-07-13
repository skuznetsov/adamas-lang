require "../../../src/compiler/hir/hir"

args = [11_u32, 13_u32] of Adamas::HIR::ValueId

zero = Adamas::HIR::Literal.new(0_u32, Adamas::HIR::TypeRef::INT32, 0_i64)
current = Adamas::HIR::Call.new(1_u32, Adamas::HIR::TypeRef::VOID, "")
current.configure_without_receiver("Thread.current", args)
scheduler = Adamas::HIR::Call.new(2_u32, Adamas::HIR::TypeRef::VOID, "")
scheduler.configure_with_receiver(1_u32, "Thread#scheduler", [] of Adamas::HIR::ValueId, false)
field = Adamas::HIR::FieldGet.new(3_u32, Adamas::HIR::TypeRef::VOID, 2_u32, "scheduler")
call = current

values = Hash(Adamas::HIR::ValueId, Adamas::HIR::Value).new
values[0_u32] = zero.as(Adamas::HIR::Value)
values[1_u32] = current.as(Adamas::HIR::Value)
values[2_u32] = scheduler.as(Adamas::HIR::Value)
values[3_u32] = field.as(Adamas::HIR::Value)
fetched = values[1_u32]?

raise "value hash lookup returned nil" unless fetched
raise "value hash lookup lost identity" unless fetched.same?(call)
raise "value hash lookup returned the wrong value type" unless fetched.is_a?(Adamas::HIR::Call)

fetched_call = fetched.as(Adamas::HIR::Call)
raise "value hash lookup changed method name" unless fetched_call.method_name == "Thread.current"
raise "value hash lookup changed args" unless fetched_call.args == args

puts "generated-hir-value-hash-call-identity-ok"
