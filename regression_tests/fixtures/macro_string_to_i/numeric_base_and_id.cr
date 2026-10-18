lib LibC
  fun putchar(c : Int32) : Int32
end

LibC.putchar({{ "41".to_i(16.9) }})
LibC.putchar({{ "42".id.to_i(16) }})
LibC.putchar(10)
