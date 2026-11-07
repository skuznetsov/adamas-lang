lib Native
  fun putchar(c : Int32) : Int32
end
struct Box(T)
  def initialize(@value : T); end
  def value : T; @value; end
end
box = Box(typeof(65)).new(65)
Native.putchar(box.value)
