class InheritedBlockShapeBase
  def self.transform(value : Int32, &block : -> Int32) : Int32
    block.call
  end
end

class InheritedBlockShapeChild < InheritedBlockShapeBase
  def self.transform(value : Bool) : Int32
    value ? 1 : 0
  end
end

InheritedBlockShapeChild.transform(7)
