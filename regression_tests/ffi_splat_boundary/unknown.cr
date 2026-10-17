@[Link("c")]
lib NamedFFIProbe
  fun write(fd : Int32, buffer : Void*, count : UInt64) : Int64
end

NamedFFIProbe.write(fd: 1, buffer: "C\n", length: 2_u64)
