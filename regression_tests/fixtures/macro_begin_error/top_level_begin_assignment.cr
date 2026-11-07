lib LibC
  fun putchar(value : Int32) : Int32
end

{% top_result = begin
     side_effect = 65
     side_effect + 1
   end %}

LibC.putchar({{ top_result }})
LibC.putchar({{ side_effect }})
LibC.putchar(10)
