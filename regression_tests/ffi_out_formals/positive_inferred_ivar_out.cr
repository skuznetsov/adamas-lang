@[Link("m")]
lib OutContractMath
  fun frexp(value : Float64, exponent : Int32*) : Float64
end

@[Link("c")]
lib OutContractOutput
  fun putchar(value : Int32) : Int32
end

class OutContractHolder
  def initialize
    OutContractMath.frexp(8.0, out @exponent)
  end

  def exponent : Int32
    @exponent
  end
end

if OutContractHolder.new.exponent == 4
  OutContractOutput.putchar(73)
else
  OutContractOutput.putchar(88)
end
OutContractOutput.putchar(10)
