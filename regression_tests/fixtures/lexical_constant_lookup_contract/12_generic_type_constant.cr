lib LibC
  fun putchar(value : Int32) : Int32
end

class LexicalConstantTag
  VALUE = 65
end

class GenericConstantReader(T)
  def self.read : Int32
    T::VALUE
  end
end

LibC.putchar(GenericConstantReader(LexicalConstantTag).read)
LibC.putchar(10)
