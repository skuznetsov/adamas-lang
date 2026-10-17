@[Link("c")]
lib NamedFFIProbe
  fun printf(format : UInt8*, ...) : Int32
end

NamedFFIProbe.printf(format: "E\n")
