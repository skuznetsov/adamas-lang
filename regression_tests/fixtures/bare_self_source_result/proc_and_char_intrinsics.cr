lib Output
  fun putchar(value : Int32) : Int32
end

struct Proc
  def invoke_zero
    call
  end
end

struct Char
  # The exact primitive declaration used by Crystal's Char#ord.
  @[Primitive(:convert)]
  def ord : Int32
  end

  def ordinal_from_self
    ord
  end
end

zero = -> { 65 }
Output.putchar(zero.invoke_zero)
Output.putchar('B'.ordinal_from_self)
Output.putchar(10)
