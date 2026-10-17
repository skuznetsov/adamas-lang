@[Link("c")]
lib ArityProbe
  fun getpid : Int32
  fun putchar(value : Int32) : Int32
  fun puts(value : UInt8*) : Int32
  fun printf(format : UInt8*, ...) : Int32
end
ArityProbe.getpid()
ArityProbe.getpid
ArityProbe.putchar(*{65})
ArityProbe.putchar(10)
ArityProbe.printf("%s%c", "B", 10)
ArityProbe.printf("C\n")
