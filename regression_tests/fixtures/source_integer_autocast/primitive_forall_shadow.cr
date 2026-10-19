lib NumericProbeC
  fun putchar(value : Int32) : Int32
end
def accept_type(value : Bool.class) : Int32
  65
end
def inspect_type(value : UInt8) : Int32 forall UInt8
  accept_type(UInt8)
end
NumericProbeC.putchar(inspect_type(true))
NumericProbeC.putchar(10)
