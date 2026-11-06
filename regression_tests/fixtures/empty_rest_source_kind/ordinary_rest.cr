@[Link("gc")]
lib RestOwnerOutput
  fun putchar(value : Int32) : Int32
end

def ordinary(value : Int32, *rest)
  RestOwnerOutput.putchar(66)
end

ordinary(65)
ordinary(65, 1)
RestOwnerOutput.putchar(10)
