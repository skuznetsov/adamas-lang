require "./helpers/macros"
macro forwarded_property
  property next : ::Int32 = marker, "next", "::Int32"
end
forwarded_property
LibC.putchar(10)
