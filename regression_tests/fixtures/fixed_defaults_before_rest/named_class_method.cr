@[Link("c")]
lib StaticIndexOutput
  fun putchar(value : Int32) : Int32
end
class StaticIndexer
  def self.emit(value : Int32 = 65, *parts) : Int32; value; end
end
StaticIndexOutput.putchar(StaticIndexer.emit())
StaticIndexOutput.putchar(StaticIndexer.emit(66))
StaticIndexOutput.putchar(10)
