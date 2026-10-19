lib LibC
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

def positional(value : Int32) : Int32
  value
end

def positional(value : Bool) : Int32
  90
end

def defaulted(value : Int32, marker : Int32 = 0) : Int32
  value
end

def defaulted(value : Bool, marker : Int32 = 0) : Int32
  90
end

def named(label value : Int32) : Int32
  value
end

def named(label value : Bool) : Int32
  90
end

def spread(first : Int32, second : Int32) : Int32
  first
end

def spread(first : Bool, second : Int32) : Int32
  90
end

def with_block(value : Int32, &block : -> Int32) : Int32
  block.call
end

def with_block(value : Bool, &block : -> Int32) : Int32
  90
end

def terminal(value : Int32) : NoReturn
  LibC.exit(value)
end

def terminal(value : Bool) : NoReturn
  LibC.exit(1)
end

pair = {68, 69}
LibC.putchar(positional(65))
LibC.putchar(defaulted(66))
LibC.putchar(named(label: 67))
LibC.putchar(spread(*pair))
LibC.putchar(with_block(70) { 69 })
terminal(0)
