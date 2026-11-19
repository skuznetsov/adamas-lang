lib LibC
  fun putchar(value : Int32) : Int32
end

class CallbackResultBox(T)
end

module CallbackEnumerable(T)
  def map(& : T -> U) : CallbackResultBox(U) forall U
    map_with_index { |entry, _index| yield entry }
  end

  def map_with_index(offset = 0, & : T, Int32 -> U) : CallbackResultBox(U) forall U
    result = CallbackResultBox(U).new
    yield callback_entry, offset
    result
  end
end

class CallbackReceiver(K, V, T)
  include CallbackEnumerable(Tuple(K, V))

  def initialize(@key : K, @value : V)
  end

  def callback_entry
    {@key, @value}
  end
end

def tuple_tag(box : CallbackResultBox(Tuple(Int32, Bool))) : Int32
  65
end

def class_tag(box : CallbackResultBox(Int32.class)) : Int32
  66
end

def number_tag(box : CallbackResultBox(Int32)) : Int32
  67
end

receiver = CallbackReceiver(Int32, Bool, Int64).new(7, true)
LibC.putchar(tuple_tag(receiver.map { |entry| entry }))
LibC.putchar(class_tag(receiver.map { |key, flag| Int32 }))
LibC.putchar(number_tag(receiver.map_with_index(3) { |entry, offset| offset }))
LibC.putchar(10)
