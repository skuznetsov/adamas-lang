lib Output
  fun putchar(c : Int32) : Int32
end

struct Proc
  def invoke(other)
    call(other)
  end
  def generic_forward(other : U) forall U
    call(other)
  end
  def invoke_zero
    call
  end
end
char_proc = ->(value : Char) { 65 }
char_proc.invoke("wrong")
