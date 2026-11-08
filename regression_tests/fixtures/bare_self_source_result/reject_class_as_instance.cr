class InvalidReader
  def value : Int32.class
    Int32
  end
  def choose(input : Int32) : Int32
    input
  end
  def run
    choose(value)
  end
end
InvalidReader.new.run
