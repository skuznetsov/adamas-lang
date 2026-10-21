lib LibC
  fun putchar(value : Int32) : Int32
end

require "./recursive_dir_order/**"
LibC.putchar(GlobChild.new.marker)
