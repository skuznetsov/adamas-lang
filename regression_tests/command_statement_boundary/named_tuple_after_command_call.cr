lib LibC
  fun putchar(value : Int32) : Int32
end

def identity(value : Int32) : Int32
  value
end

def emit(value : Int32) : Int32
  LibC.putchar(value)
  value
end

def build_tuple
  if true
    field = identity 65
    {
      queue_name: emit(field),
      message_count: emit(66),
      consumer_count: emit(67),
    }
  else
    {
      queue_name: 0,
      message_count: 0,
      consumer_count: 0,
    }
  end
end

# Do not invoke named-tuple getters: the field expressions themselves make
# construction of the next-line named tuple observable without a prelude.
build_tuple
