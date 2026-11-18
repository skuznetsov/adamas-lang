require "object/properties"

lib LibC
  fun putchar(code : Int32) : Int32
end

class Entry
  def self.make
    LibC.putchar(73)
    new
  end
end

class EagerStore
  getter entry : Entry? = Entry.make

  def clear
    @entry = nil
  end
end

class LazyStore
  getter entry : Entry? do
    Entry.make
  end

  def clear
    @entry = nil
  end
end

def read_and_clear(store)
  LibC.putchar(65)
  LibC.putchar(store.entry ? 89 : 78)
  LibC.putchar(store.entry ? 89 : 78)
  store.clear
  LibC.putchar(store.entry ? 89 : 78)
  LibC.putchar(10)
end

read_and_clear(EagerStore.new)
read_and_clear(LazyStore.new)
