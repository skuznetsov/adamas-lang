lib LibC
  fun putchar(value : Int32) : Int32
end

struct Reader
  @available : Bool
  @current : Char

  def initialize(@available : Bool, @current : Char)
  end

  def maybe : Char?
    if @available
      @current
    else
      nil
    end
  end

  def next_char : Char
    maybe || '\0'
  end
end

LibC.putchar(Reader.new(true, 'A').next_char.ord)
LibC.putchar(Reader.new(false, 'A').next_char.ord)
LibC.putchar(10)
