@[Link("c")]
lib OutContractNamed
  fun parse = strtol(input : UInt8*, endptr : UInt8**, base : Int32) : Int64
  fun putchar(value : Int32) : Int32
end

parsed = OutContractNamed.parse(base: 10, endptr: out tail, input: "65!")
OutContractNamed.putchar(parsed.to_i32)
OutContractNamed.putchar(tail.value.to_i32)
OutContractNamed.putchar(10)

parsed_splat = OutContractNamed.parse(*{"66!"}, base: 10, endptr: out tail_splat)
OutContractNamed.putchar(parsed_splat.to_i32)
OutContractNamed.putchar(tail_splat.value.to_i32)
OutContractNamed.putchar(10)

def named_input
  OutContractNamed.putchar(65)
  "67!"
end

def named_base
  OutContractNamed.putchar(67)
  10
end

# Crystal normalizes named expressions to declaration order before evaluation.
parsed_order = OutContractNamed.parse(base: named_base, endptr: out tail_order, input: named_input)
OutContractNamed.putchar(parsed_order.to_i32)
OutContractNamed.putchar(tail_order.value.to_i32)
OutContractNamed.putchar(10)
