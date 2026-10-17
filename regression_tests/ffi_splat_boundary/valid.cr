@[Link("c")]
lib NamedFFIProbe
  fun write(fd : Int32, buffer : Void*, count : UInt64) : Int64
end

NamedFFIProbe.write(count: 2_u64, buffer: "A\n", fd: 1)
NamedFFIProbe.write(1, count: 2_u64, buffer: "B\n")
