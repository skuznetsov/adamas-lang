lib StringIndexProbeC
  fun putchar(value : Int32) : Int32
end

struct Range(B, E)
  def initialize(@begin : B, @end : E, @exclusive : Bool = false)
  end
end

class TextIndex
end

class String
  def [](index : Int32) : Char
    'A'
  end

  def [](range : Range) : String
    "B"
  end

  def [](index : TextIndex) : Bool
    true
  end
end

def char_code(value : Char) : Int32
  value.ord
end

def text_code(value : String) : Int32
  66
end

def bool_code(value : Bool) : Int32
  value ? 67 : 88
end

alias NullableIndexRange = Range(Int64?, Int64?)

def bound(index : Int64, open : Bool) : Int64?
  open ? nil : index
end

def make_range(open : Bool) : NullableIndexRange
  Range.new(bound(0_i64, open), bound(1_i64, !open))
end

def indexed_text(text : String, range : NullableIndexRange) : Int32
  result = text[range]
  text_code(result)
end

text = "probe"
StringIndexProbeC.putchar(char_code(text[0]))
StringIndexProbeC.putchar(indexed_text(text, make_range(true)))
StringIndexProbeC.putchar(bool_code(text[TextIndex.new]))
StringIndexProbeC.putchar(10)
