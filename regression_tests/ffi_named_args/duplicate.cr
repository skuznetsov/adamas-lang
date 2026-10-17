@[Link("c")]
lib NamedFFIProbe
  fun write(fd : Int32, buffer : Void*, count : UInt64) : Int64
end

NamedFFIProbe.write(1, fd: 1, buffer: "C\n", count: 2_u64)
