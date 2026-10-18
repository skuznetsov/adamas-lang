lib LibC
  fun putchar(c : Int32) : Int32
end

LibC.putchar({{ " +65 ".to_i }})
LibC.putchar({{ "-65".to_i + 131 }})
LibC.putchar(10)
