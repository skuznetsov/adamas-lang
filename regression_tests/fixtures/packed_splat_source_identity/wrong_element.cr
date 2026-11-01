class PackedWrongElement
  def accept(*values : Int32) : Int32
    1
  end
end

PackedWrongElement.new.accept(true)
