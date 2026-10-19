def consume(first : Int32, second : Int32) : Int32
  first + second
end

def consume(first : Bool, second : Int32) : Int32
  second
end

consume(1, "wrong")
