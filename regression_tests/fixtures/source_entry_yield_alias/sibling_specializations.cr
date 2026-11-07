@[Link(ldflags: "@@SOURCE_ENTRY_HELPER_OBJECT@@")]
lib EntryNative
  fun start = adamas_entry_start : Void*
  fun step = adamas_entry_step(value : Void*) : Void*
  fun inspect = adamas_entry_inspect(value : Void*) : Int32
  fun putchar(value : Int32) : Int32
end
class SourceProbe
  def self.identity(value)
    value
  end
  def self.source(value, &)
    yield value
  end
  def self.project(seed, &)
    original = seed
    source(seed) do |address|
      seed = identity(seed)
      return yield original
    end
  end
end
def consume(value : Void*)
  EntryNative.putchar(EntryNative.inspect(value))
end
def consume(value : Int64)
  if value == 17_i64
    EntryNative.putchar(67)
  end
end
consume(SourceProbe.project(EntryNative.start) { |original| original })
consume(SourceProbe.project(17_i64) { |original| original })
consume(SourceProbe.project(EntryNative.start) { |original| original })
EntryNative.putchar(10)
