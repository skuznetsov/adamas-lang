lib ProbeC
  fun putchar(value : Int32) : Int32
end

def source_discard : Void
  ProbeC.putchar(65)
  17
end

fun main(argc : Int32, argv : UInt8**) : Void
  source_discard
end
