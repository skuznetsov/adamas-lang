lib Output
  fun putchar(c : Int32) : Int32
end

class CapturedInitializerResultOwner
  def initialize(@marker : Int32, &@callback)
    @callback
  end

  def marker : Int32
    @marker
  end
end

first = CapturedInitializerResultOwner.new(65) { 1 }
second = CapturedInitializerResultOwner.new(66) { 2 }
Output.putchar(first.marker)
Output.putchar(second.marker)
Output.putchar(10)
