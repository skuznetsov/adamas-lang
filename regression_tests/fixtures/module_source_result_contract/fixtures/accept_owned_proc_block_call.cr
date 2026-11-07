lib LibC
  fun putchar(c : Int32) : Int32
end

class OwnedTypedBlockEntry
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end

  def self.new(&block : self)
    block
  end
end

module OwnedTypedBlockFactory
  def self.value(&block : ->) : OwnedTypedBlockEntry.class | OwnedTypedBlockEntry
    block.call
    OwnedTypedBlockEntry.new
  end
end

def owned_typed_inline(&block : -> T) : T forall T
  yield
end

def owned_typed_send(callback : Proc(OwnedTypedBlockEntry, Int32), &block : -> T) : Int32 forall T
  callback.call(owned_typed_inline { yield })
end

callback = Proc(OwnedTypedBlockEntry, Int32).new { |_entry| 1 }
owned_typed_send(callback) do
  OwnedTypedBlockFactory.value { LibC.putchar(65) }
end
LibC.putchar(10)
