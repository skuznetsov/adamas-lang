@[Link("c")]
lib NamedFFIProbe
  fun parse = strtol(input : UInt8*, endptr : UInt8**, base : Int32) : Int64
  fun putchar(value : Int32) : Int32
end

parsed = NamedFFIProbe.parse(base: 10, endptr: out tail, input: "65!")
NamedFFIProbe.putchar(parsed.to_i32)
NamedFFIProbe.putchar(tail.value.to_i32)
NamedFFIProbe.putchar(10)

parsed_splat = NamedFFIProbe.parse(*{"66!"}, base: 10, endptr: out tail_splat)
NamedFFIProbe.putchar(parsed_splat.to_i32)
NamedFFIProbe.putchar(tail_splat.value.to_i32)
NamedFFIProbe.putchar(10)

def named_input
  NamedFFIProbe.putchar(65)
  "67!"
end

def named_base
  NamedFFIProbe.putchar(67)
  10
end

# Crystal normalizes named expressions to declaration order before evaluation.
parsed_order = NamedFFIProbe.parse(base: named_base, endptr: out tail_order, input: named_input)
NamedFFIProbe.putchar(parsed_order.to_i32)
NamedFFIProbe.putchar(tail_order.value.to_i32)
NamedFFIProbe.putchar(10)
