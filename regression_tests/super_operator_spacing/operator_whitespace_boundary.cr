lib SuperSignBoundaryC
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  SuperSignBoundaryC.exit(92_i32)
end

class SuperSignBoundaryParent
  def plus_spaced(value : Int32) : Int32
    value + 60
  end

  def plus_adjacent(value : Int32) : Int32
    value + 60
  end

  def minus_spaced(value : Int32) : Int32
    value + 60
  end

  def minus_adjacent(value : Int32) : Int32
    value + 60
  end

  def plus_tab(value : Int32) : Int32
    value + 60
  end

  def minus_tab(value : Int32) : Int32
    value + 60
  end
end

class SuperSignBoundaryChild < SuperSignBoundaryParent
  def plus_spaced(value : Int32) : Int32
    super + 5
  end

  def plus_adjacent(value : Int32) : Int32
    super +5
  end

  def minus_spaced(value : Int32) : Int32
    super - 5
  end

  def minus_adjacent(value : Int32) : Int32
    super -5
  end

  def plus_tab(value : Int32) : Int32
    super +	5
  end

  def minus_tab(value : Int32) : Int32
    super -	5
  end
end

probe = SuperSignBoundaryChild.new
SuperSignBoundaryC.putchar(probe.plus_spaced(6))
SuperSignBoundaryC.putchar(probe.plus_tab(6))
SuperSignBoundaryC.putchar(probe.plus_adjacent(6))
SuperSignBoundaryC.putchar(probe.minus_spaced(6))
SuperSignBoundaryC.putchar(probe.minus_tab(6))
SuperSignBoundaryC.putchar(probe.minus_adjacent(6))
