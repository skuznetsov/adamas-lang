lib C
  fun putchar(value : Int32) : Int32
end

struct Receiver
  def self.mark(value : Int32) : Int32
    value &+ 1
  end
  def mark(value : Int32) : Int32
    value &+ 3
  end
  def self.new(value : Int32) : Int32
    value &+ 1
  end
  def new(value : Int32) : Int32
    value &+ 3
  end
end

class Forwarder
  def mark_type_first(owner, value, flag)
    owner.mark(value)
  end

  def mark_instance_first(subject owner, payload value, flag)
    owner.mark(value)
  end

  def build_type_first(owner, value, flag)
    owner.new(value)
  end

  def build_instance_first(owner, value, flag)
    owner.new(value)
  end

  def run
    instance = uninitialized Receiver
    C.putchar(mark_type_first(Receiver, 64, flag: false))
    C.putchar(mark_type_first(instance, 64, flag: false))
    C.putchar(mark_instance_first(flag: false, payload: 64, subject: instance))
    C.putchar(mark_instance_first(subject: Receiver, flag: false, payload: 64))
    C.putchar(build_type_first(Receiver, 64, flag: false))
    C.putchar(build_type_first(instance, 64, flag: false))
    C.putchar(build_instance_first(instance, 64, flag: false))
    C.putchar(build_instance_first(Receiver, 64, flag: false))
    C.putchar(10)
  end
end
Forwarder.new.run
