lib LibC
  fun exit(status : Int32) : NoReturn
end

def terminal : NoReturn
  LibC.exit(0)
end

def consume(first : Int32, second : Int32) : Int32
  first + second
end

consume(1, terminal)
