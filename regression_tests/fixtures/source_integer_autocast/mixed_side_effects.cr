lib NumericProbeC
  fun putchar(value : Int32) : Int32
end
def mark : Int32
  NumericProbeC.putchar(65)
  1
end
def consume(first : Int32, second : UInt16) : Int32
  second == 2_u16 ? 66 : 67
end
NumericProbeC.putchar(consume(mark, 2))
NumericProbeC.putchar(10)
