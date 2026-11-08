class Box
  def value=(value : Bool)
    Int32
  end
end

def accept(value : Int32) : Int32
  65
end

accept(Box.new.value = true)
