lib LibC
  fun putchar(c : Int32) : Int32
end
macro declare_bridge
  fun adamas_parser_value : Int32
    65
  end
end
declare_bridge
LibC.putchar(adamas_parser_value)
LibC.putchar(10)
