lib LibC
  fun putchar(value : Int32) : Int32
end

struct Reader
  @available : Bool

  def initialize(@available : Bool)
  end

  def maybe : Char?
    if @available
      'A'
    else
      nil
    end
  end

  def next_char : Char
    maybe || '\0'
  end
end

LibC.putchar(Reader.new(true).next_char.ord)
LibC.putchar(Reader.new(false).next_char.ord)
LibC.putchar(10)
