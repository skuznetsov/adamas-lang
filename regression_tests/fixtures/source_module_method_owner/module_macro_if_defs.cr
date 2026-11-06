lib C
  fun putchar(value : Int32) : Int32
end
module SizeTrait
  {% if true %}
    def size : Int32
      66
    end
  {% end %}
  def source_size : Int32
    size
  end
end
struct Tuple
  include SizeTrait
  def size : Int32
    65
  end
end
pair = {1, 2}
C.putchar(pair.size)
C.putchar(pair.source_size)
