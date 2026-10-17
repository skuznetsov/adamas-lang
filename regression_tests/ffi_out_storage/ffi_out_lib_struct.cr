@[Link(ldflags: "@@OUT_HELPER_OBJECT@@")]
lib OutLocalPairProbe
  struct Pair
    read_end : Int32
    write_end : Int32
  end

  fun fill_pair = adamas_out_local_fill_pair(pair : Pair*) : Int32
  fun putchar(value : Int32) : Int32
end

status = OutLocalPairProbe.fill_pair(out descriptors)
if status == 0 && descriptors.read_end == 65 && descriptors.write_end == 66
  OutLocalPairProbe.putchar(80)
else
  OutLocalPairProbe.putchar(88)
end
OutLocalPairProbe.putchar(10)
