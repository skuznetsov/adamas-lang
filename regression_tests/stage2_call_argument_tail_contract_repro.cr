def adamas_two_args(a : Int32, b : Int32)
  a + b
end

raise "top-level argument tail" unless adamas_two_args(2, 3) == 5

struct UInt8
  def adamas_two_args(other : Int32)
    self.to_i + other
  end
end

raise "instance argument tail" unless 2_u8.adamas_two_args(3) == 5
