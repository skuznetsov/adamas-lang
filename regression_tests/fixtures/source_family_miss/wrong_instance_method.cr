class Consumer
  def consume(value : Int32) : Int32
    value
  end

  def consume(value : Bool) : Int32
    0
  end
end

Consumer.new.consume("wrong")
