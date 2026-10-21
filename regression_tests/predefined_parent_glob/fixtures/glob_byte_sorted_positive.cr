lib LibC
  fun putchar(value : Int32) : Int32
end

require "./byte_positive/*"
LibC.putchar(GlobChild.new.marker)
