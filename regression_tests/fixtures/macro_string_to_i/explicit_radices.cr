lib LibC
  fun putchar(c : Int32) : Int32
end

LibC.putchar({{ "41".to_i(16) }})
LibC.putchar({{ "1000010".to_i(2) }})
LibC.putchar({{ "103".to_i(8) }})
LibC.putchar({{ "1w".to_i(36) }})
LibC.putchar(10)
