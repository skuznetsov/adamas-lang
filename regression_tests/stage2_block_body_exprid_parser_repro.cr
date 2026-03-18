fun foo(a : Int32, b : Int32, overflow : Int32*) : Int32
  overflow.value = 0
  sa = a >> 31
  abs_a = (a ^ sa) &- sa
  sb = b >> 31
  abs_b = (b ^ sb) &- sb
  x1 = 1
  x2 = 2
  x3 = 3
  x4 = 4
  if abs_a < 2
    return 0
  end
  0
end
