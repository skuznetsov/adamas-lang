lib LibC
  fun putchar(c : Int32) : Int32
end

class YieldGuardRefusalEntry
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end

  def self.new(&block : self)
    block
  end
end

module YieldGuardRefusalFactory
  def self.value(flag : Bool, &unused : ->) : YieldGuardRefusalEntry.class | YieldGuardRefusalEntry
    if flag
      YieldGuardRefusalEntry
    else
      YieldGuardRefusalEntry.new
    end
  end
end

def yield_guard_inline(&block : -> T) : T forall T
  yield
end

def yield_guard_send(callback : Proc(YieldGuardRefusalEntry.class | YieldGuardRefusalEntry, Int32), &block : -> T) : Int32 forall T
  callback.call(yield_guard_inline { yield })
end

callback = Proc(YieldGuardRefusalEntry.class | YieldGuardRefusalEntry, Int32).new { |_entry| LibC.putchar(65) }
yield_guard_send(callback) do
  YieldGuardRefusalFactory.value(false) {}
end
LibC.putchar(10)
