@[Link("gc")]
lib RestOwnerOutput
  fun putchar(value : Int32) : Int32
end

def choose(value : Int32.class, *rest)
  RestOwnerOutput.putchar(65)
end

def choose(value : Int32, *rest)
  RestOwnerOutput.putchar(73)
end

choose(Int32, 9)
choose(7, 9)
choose(Int32)
choose(7)
RestOwnerOutput.putchar(10)
