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

def warm
  forward
end

def forward(*rest)
  choose(Int32, *rest)
end

warm
choose(Int32)
RestOwnerOutput.putchar(10)
