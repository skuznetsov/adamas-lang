class DepthRefusalEntry
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end

  def self.new(&block : self)
    block
  end
end

module DepthRefusalFactory
  def self.leaf(flag : Bool) : DepthRefusalEntry.class | DepthRefusalEntry
    if flag
      DepthRefusalEntry
    else
      DepthRefusalEntry.new
    end
  end

  def self.middle(flag : Bool) : DepthRefusalEntry.class | DepthRefusalEntry
    leaf(flag)
  end

  def self.outer(flag : Bool) : DepthRefusalEntry.class | DepthRefusalEntry
    middle(flag)
  end

  def self.send_value(callback : Proc(DepthRefusalEntry, Int32), flag : Bool) : Int32
    callback.call(outer(flag))
  end
end

callback = Proc(DepthRefusalEntry, Int32).new { |_entry| 1 }
DepthRefusalFactory.send_value(callback, true)
