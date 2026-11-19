lib UnionTagNative
  fun putchar(value : Int32) : Int32
end

class TaggedReference
  def code : Int32
    65
  end
end

struct TaggedValue
  def code : Int32
    66
  end
end

def pick(reference : Bool) : TaggedReference | TaggedValue
  if reference
    TaggedReference.new
  else
    TaggedValue.new
  end
end

def show(value : TaggedReference | TaggedValue)
  UnionTagNative.putchar(value.code)
  UnionTagNative.putchar(value.code())
end

show(pick(true))
show(pick(false))
UnionTagNative.putchar(10)
