lib LibC
  fun putchar(c : Int32) : Int32
end
macro declare_bridge
  lib BridgeC
    {% if true %}
      fun bridge_a = putchar(c : Int32) : Int32
      @[Raises]
      fun bridge_b = putchar(c : Int32) : Int32
    {% end %}
  end
end
declare_bridge
LibC.putchar(65)
LibC.putchar(10)
