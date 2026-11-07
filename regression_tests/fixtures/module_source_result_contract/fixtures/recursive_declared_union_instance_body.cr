class RecursiveRefusalEntry
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end

  def self.new(&block : self)
    block
  end
end

module RecursiveRefusalFactory
  def self.value(depth : Int32, callback : Proc(RecursiveRefusalEntry, RecursiveRefusalEntry)) : RecursiveRefusalEntry.class | RecursiveRefusalEntry
    if depth == 0
      RecursiveRefusalEntry.new
    else
      callback.call(value(depth - 1, callback))
    end
  end
end

callback = Proc(RecursiveRefusalEntry, RecursiveRefusalEntry).new { |_entry| RecursiveRefusalEntry.new }
RecursiveRefusalFactory.value(1, callback)
