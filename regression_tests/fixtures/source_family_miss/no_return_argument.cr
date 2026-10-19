lib LibC
  fun exit(status : Int32) : NoReturn
end

def consume(first : Int32, second : Int32) : Int32
  first + second
end

consume(1, LibC.exit(0))
