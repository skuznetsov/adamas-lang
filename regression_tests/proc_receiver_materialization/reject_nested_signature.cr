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
inner = ->(value : Int32) { 65 }
outer = ->(callback : Proc(Char, Int32)) { callback.call('x') }
outer.invoke(inner)
