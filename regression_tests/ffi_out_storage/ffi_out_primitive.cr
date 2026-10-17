@[Link("m")]
lib OutLocalMath
  fun frexp(value : Float64, exponent : Int32*) : Float64
end

@[Link("c")]
lib OutLocalOutput
  fun putchar(value : Int32) : Int32
end

fraction = OutLocalMath.frexp(8.0, out exponent)
discarded_a = OutLocalMath.frexp(8.0, out _)
discarded_b = OutLocalMath.frexp(8.0, out _)
if exponent == 4 && fraction == 0.5 && discarded_a == 0.5 && discarded_b == 0.5
  OutLocalOutput.putchar(79)
else
  OutLocalOutput.putchar(78)
end
OutLocalOutput.putchar(10)
