class RequiredReader
  def value(input : Int32) : Int32
    input
  end
  def run
    self.value()
  end
end
RequiredReader.new.run
