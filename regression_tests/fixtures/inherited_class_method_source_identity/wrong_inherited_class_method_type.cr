class InheritedTypeParent
  def self.parse(value : String) : Int32
    1
  end
end

class InheritedTypeChild < InheritedTypeParent
  def self.parse(value : Bool, &block : -> Int32) : Int32
    block.call
  end
end

InheritedTypeChild.parse(1)
