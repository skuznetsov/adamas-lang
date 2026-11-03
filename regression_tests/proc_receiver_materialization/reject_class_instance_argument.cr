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
class Owner
end
class_proc = ->(owner : Owner.class) { 65 }
class_proc.invoke(Owner.new)
