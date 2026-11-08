lib LibC
  fun putchar(value : Int32) : Int32
end

struct Reader
  @available : Bool
  @current : Char

  def initialize(@available : Bool)
    @current = '\0'
  end

  private def decode : Char
    @current = 'A'
  end

  def maybe : Char?
    if @available
      decode
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
