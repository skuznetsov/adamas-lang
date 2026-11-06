lib C
  fun putchar(value : Int32) : Int32
end

class InstanceSourceVoidProbe
  def emit : Void
    C.putchar(69) # E: call side effect
    91
  end

  def classify(value : Nil)
    C.putchar(78) # N: Nil overload
    nil
  end

  def classify(value : Int32)
    C.putchar(73) # I: Int32 overload
    nil
  end

  def bare_control
    classify(emit)
    nil
  end

  def parenthesized_control
    classify(emit())
    nil
  end

  def explicit_self_control
    classify(self.emit)
    nil
  end
end

probe = InstanceSourceVoidProbe.new
probe.bare_control
probe.parenthesized_control
probe.explicit_self_control
C.putchar(10)
