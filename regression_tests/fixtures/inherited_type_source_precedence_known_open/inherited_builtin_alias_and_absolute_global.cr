lib C
  fun putchar(c : Int32) : Int32
end

class NameBase
  alias String = Int32
end

class NameChild < NameBase
  def self.inherited_name(value : String = 65) : String
    value
  end

  def self.absolute_global(value : ::String = "S") : ::String
    value
  end
end

class TypeSink
  def self.accept_int32(value : Int32)
    C.putchar(65)
  end

  def self.accept_string(value : ::String)
    C.putchar(83)
  end
end

TypeSink.accept_int32(NameChild.inherited_name)
TypeSink.accept_string(NameChild.absolute_global)
C.putchar(10)
