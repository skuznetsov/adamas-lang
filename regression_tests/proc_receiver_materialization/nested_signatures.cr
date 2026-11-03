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
inner = ->(value : Char) { 65 }
outer = ->(callback : Proc(Char, Int32)) { callback.call('x') }
Output.putchar(outer.invoke(inner))
Output.putchar(inner.generic_forward('x'))
Output.putchar(10)
