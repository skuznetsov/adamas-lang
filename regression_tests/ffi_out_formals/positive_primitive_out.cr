@[Link("m")]
lib OutContractMath
  fun frexp(value : Float64, exponent : Int32*) : Float64
end

@[Link("c")]
lib OutContractOutput
  fun putchar(value : Int32) : Int32
end

fraction = OutContractMath.frexp(8.0, out exponent)
discarded = OutContractMath.frexp(8.0, out _)
if fraction == 0.5 && exponent == 4 && discarded == 0.5
  OutContractOutput.putchar(79)
else
  OutContractOutput.putchar(78)
end
OutContractOutput.putchar(10)
