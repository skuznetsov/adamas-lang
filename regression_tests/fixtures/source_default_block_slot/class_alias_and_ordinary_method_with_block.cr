@[Link("c")]
lib SourceBlockSlotOutput
  fun putchar(value : Int32) : Int32
end

class AliasBlockMethod
  def self.run(seed = 6, &block : -> Int32)
    (yield) &+ seed
  end
end

alias AliasBlockMethodName = AliasBlockMethod

class OrdinaryBlockMethod
  def initialize(@base : Int32)
  end

  def run(offset = 10, &block : -> Int32)
    (yield) &+ @base &+ offset
  end
end

class_value = AliasBlockMethodName.run { 65 }
SourceBlockSlotOutput.putchar(class_value)
SourceBlockSlotOutput.putchar(10)

receiver = OrdinaryBlockMethod.new(2)
instance_value = receiver.run { 65 }
SourceBlockSlotOutput.putchar(instance_value)
SourceBlockSlotOutput.putchar(10)
