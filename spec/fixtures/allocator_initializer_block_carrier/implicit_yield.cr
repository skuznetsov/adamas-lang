lib Output
  fun putchar(c : Int32) : Int32
end

class RawInitializerCarrier
  @name : String?

  def initialize(@name : String? = nil)
    @code = 17
    yield
  end

  def initialize
    @name = nil
    @code = 39
  end
end

RawInitializerCarrier.new("name") { Output.putchar(65) }
Output.putchar(10)
