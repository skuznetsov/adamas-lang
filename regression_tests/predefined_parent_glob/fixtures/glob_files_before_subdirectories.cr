lib LibC
  fun putchar(value : Int32) : Int32
end

require "./files_before_dirs/**"
LibC.putchar(GlobChild.new.marker)
