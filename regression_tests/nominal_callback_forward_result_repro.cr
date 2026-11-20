@[Link("c")]
lib Native
  fun putchar(value : Int32) : Int32
end

class ResultBox(T)
end

def map_entry(entry : T, & : T -> U) : ResultBox(U) forall T, U
  map_entry_with_index(entry) { |item, _index| yield item }
end

def map_entry_with_index(entry : T, & : T, Int32 -> U) : ResultBox(U) forall T, U
  result = ResultBox(U).new
  yield entry, 0
  result
end

abstract class FirstValue
end

class FirstLeft < FirstValue
end

class FirstRight < FirstValue
end

class FirstKey < FirstValue
  def initialize(@name : String)
  end
end

class FirstEntry < FirstValue
  def initialize(@key : FirstValue, @entry : FirstValue)
  end
end

abstract class SecondValue
end

class SecondLeft < SecondValue
end

class SecondMixedEntry < SecondValue
  def initialize(@name : String, @entry : SecondValue)
  end
end

class UnrelatedEntry
  def initialize(@key : FirstValue, @entry : FirstValue)
  end
end

class WrongEntry < FirstValue
  def initialize(@key : FirstValue, @entry : String)
  end
end

def first_result(value : FirstValue)
  map_entry({"key", value}) do |key_name, entry_value|
    key = FirstKey.new(key_name).as(FirstValue)
    checked_entry = entry_value
    FirstEntry.new(key, checked_entry).as(FirstValue)
  end
end

def second_result(value : SecondValue)
  map_entry({"key", value}) do |key_name, entry_value|
    checked_entry = entry_value
    SecondMixedEntry.new(key_name, checked_entry).as(SecondValue)
  end
end

def first_tag(result : ResultBox(FirstValue)) : Int32
  65
end

def second_tag(result : ResultBox(SecondValue)) : Int32
  66
end

Native.putchar(first_tag(first_result(FirstLeft.new)))
Native.putchar(first_tag(first_result(FirstRight.new)))
Native.putchar(second_tag(second_result(SecondLeft.new)))
Native.putchar(10)
