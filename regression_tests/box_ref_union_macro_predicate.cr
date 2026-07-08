# Regression: `Box.box` / `Box.unbox` are gated on
#   {% if T < Pointer || T.union_types.all? { |t| t == Nil || t < Reference } %}
# The hand-rolled macro-condition evaluator (try_evaluate_macro_condition) could
# not walk `Array#all?`/`any?` with a block, so the condition was reported as
# unevaluable; lower_macro_if then emitted a nil literal and the whole method
# body collapsed to `ret null`. `Box(String).box`/`.unbox` returned NULL instead
# of round-tripping the pointer — a latent no-op in every callback/closure that
# boxes a reference type through a `Void*`.
#
# EXPECT: BOX_UNION_PRED_OK

s = "hello world"
ptr = Box(String).box(s)
if ptr.null?
  puts "BOX_UNION_PRED_FAIL null pointer from box"
else
  back = Box(String).unbox(ptr)
  if back == "hello world"
    puts "BOX_UNION_PRED_OK"
  else
    puts "BOX_UNION_PRED_FAIL back=#{back}"
  end
end
STDOUT.flush
