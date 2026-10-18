def invoke_zero_arrow(callback : () -> Nil) : Bool
  callback.call
  true
end

def invoke_zero_generic(callback : Proc(Nil)) : Bool
  callback.call
  true
end

def invoke_pointer_pair(callback : (Void*, Void*) -> Int32) : Int32
  callback.call(Pointer(Void).null, Pointer(Void).null)
end

def invoke_singleton_grouped(callback : (Int32) -> String) : Int32
  callback.call(31).size
end

def invoke_generic_proc(callback : Proc(Int32, String)) : Int32
  callback.call(7).size
end

def invoke_nested_proc(callback : ((String, Int32 -> Int32)) -> Bool) : Bool
  operation = ->(text : String, amount : Int32) { text.size + amount }
  callback.call(operation)
end

def invoke_grouped_union(callback : (String | Nil, Int32) -> Bool) : Bool
  callback.call(nil, 3)
end

def invoke_nested_proc_with_sibling(callback : ((String, Int32 -> Int32), Bool) -> Bool) : Bool
  operation = ->(text : String, amount : Int32) { text.size + amount }
  callback.call(operation, true)
end

puts invoke_zero_arrow(-> { nil })
puts invoke_zero_generic(-> { nil })
puts invoke_pointer_pair(->(left : Void*, right : Void*) { 37 })
puts invoke_singleton_grouped(->(value : Int32) { value.to_s })
puts invoke_generic_proc(->(value : Int32) { value.to_s })
puts invoke_nested_proc(->(operation : Proc(String, Int32, Int32)) {
  operation.call("x", 2) == 3
})
puts invoke_grouped_union(->(text : String?, amount : Int32) {
  text.nil? && amount == 3
})
puts invoke_nested_proc_with_sibling(->(operation : Proc(String, Int32, Int32), enabled : Bool) {
  enabled && operation.call("x", 2) == 3
})
