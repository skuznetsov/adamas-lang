lib LibC
  fun putchar(c : Int32) : Int32
end

@[Flags]
enum Bits
  Read = 1
  Write = 4
  Execute
end

LibC.putchar(Bits::Execute.value == 8 ? 65 : 88)
LibC.putchar(10)
