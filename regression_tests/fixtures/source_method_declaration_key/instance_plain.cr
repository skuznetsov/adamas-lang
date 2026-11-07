lib C
  fun putchar(c : Int32) : Int32
end
class Probe
 def value
 66
 end
end
class Probe
 def value
 65
 end
end
C.putchar(Probe.new.value)
C.putchar(10)
