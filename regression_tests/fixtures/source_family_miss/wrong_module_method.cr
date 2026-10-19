module Consumer
  def self.consume(value : Int32) : Int32
    value
  end

  def self.consume(value : Bool) : Int32
    0
  end
end

Consumer.consume("wrong")
