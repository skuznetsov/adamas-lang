lib Output
  fun putchar(c : Int32) : Int32
end

class HeapInitializerCarrier
  def initialize(&@callback : -> Int32)
    0
  end

  def run
    @callback.call
  end
end

owner = HeapInitializerCarrier.new { Output.putchar(65) }
owner.run
Output.putchar(10)
