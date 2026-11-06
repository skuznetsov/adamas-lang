@[Link("c")]
lib GenericDefaultC
  fun putchar(value : Int32) : Int32
end
class SourceGenericDefaults(T)
  def self.call(seed : T = 65, &block : T -> Int32)
    yield seed
  end
end
SourceGenericDefaults(String).call { |value| 65 }
