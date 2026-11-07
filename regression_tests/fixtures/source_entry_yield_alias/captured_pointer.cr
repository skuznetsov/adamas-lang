@[Link(ldflags: "@@SOURCE_ENTRY_HELPER_OBJECT@@")]
lib EntryNative
  fun start = adamas_entry_start : Void*
  fun step = adamas_entry_step(value : Void*) : Void*
  fun inspect = adamas_entry_inspect(value : Void*) : Int32
  fun putchar(value : Int32) : Int32
end
class SourceProbe
  def self.source(value, &)
    yield value
  end
  def self.project(seed, &)
    original = seed
    source(seed) do |address|
      seed = EntryNative.step(seed)
      return yield original, address
    end
  end
end
value = SourceProbe.project(EntryNative.start) { |original, address| original }
EntryNative.putchar(EntryNative.inspect(value))
EntryNative.putchar(10)
