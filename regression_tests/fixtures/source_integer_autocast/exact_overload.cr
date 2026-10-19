lib NumericProbeC
  fun putchar(value : Int32) : Int32
end
def consume(value : UInt16) : Int32
  66
end
def consume(value : Int32) : Int32
  65
end
NumericProbeC.putchar(consume(65))
NumericProbeC.putchar(10)
