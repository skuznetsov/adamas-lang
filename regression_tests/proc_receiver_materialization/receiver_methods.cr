lib Output
  fun putchar(c : Int32) : Int32
end

class ProcReceiverMaterializationOwner
  def self.class_value : Int32
    66
  end

  def instance_value : Int32
    65
  end
end

struct Proc
  def invoke(other)
    call(other)
  end

  def invoke_explicit(other)
    self.call(other)
  end

  def invoke_zero
    call
  end

  def invoke_zero_explicit
    self.call
  end

  def forwarded(other)
    invoke(other)
  end
end

char_proc = ->(value : Char) { 65 }
int_proc = ->(value : Int32) { value }
class_proc = ->(owner : ProcReceiverMaterializationOwner.class) { owner.class_value }
instance_proc = ->(owner : ProcReceiverMaterializationOwner) { owner.instance_value }
zero_proc = -> { 67 }

Output.putchar(char_proc.invoke('x'))
Output.putchar(char_proc.invoke_explicit('x'))
Output.putchar(int_proc.forwarded(66))
Output.putchar(class_proc.invoke(ProcReceiverMaterializationOwner))
Output.putchar(instance_proc.invoke(ProcReceiverMaterializationOwner.new))
Output.putchar(zero_proc.invoke_zero)
Output.putchar(zero_proc.invoke_zero_explicit)
Output.putchar(10)
