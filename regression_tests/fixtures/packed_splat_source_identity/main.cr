require "object/properties"
require "comparable"
require "tuple"

lib C
  fun putchar(value : Int32) : Int32
end

class PackedTypedGetter
  def initialize(@value : Int32)
  end

  getter value : Int32

  def value(*args : Int32) : Int32
    if args.size == 1
      66
    else
      67
    end
  end
end

class PackedUntypedRest
  def value(*args) : Int32
    if args.size == 1
      68
    else
      69
    end
  end
end

class PackedInt64Rest
  def value(*args : Int64) : Int32
    if args.size == 1
      70
    else
      71
    end
  end
end

class PackedFixedFirst
  def pick(value : Int32) : Int32
    69
  end

  def pick(*values : Int32) : Int32
    70
  end
end

class PackedRestFirst
  def pick(*values : Int32) : Int32
    70
  end

  def pick(value : Int32) : Int32
    69
  end
end

C.putchar(PackedTypedGetter.new(65).value)
typed = PackedTypedGetter.new(65)
C.putchar(typed.value(1))
C.putchar(typed.value(1, 2))
untyped = PackedUntypedRest.new
first : Int64 = 1_i64
second : Int64 = 2_i64
C.putchar(untyped.value(first))
C.putchar(untyped.value(first, second))
int64 = PackedInt64Rest.new
C.putchar(int64.value(first))
C.putchar(int64.value(first, second))
fixed_first = PackedFixedFirst.new
C.putchar(fixed_first.pick(1))
C.putchar(fixed_first.pick(1, 2))
rest_first = PackedRestFirst.new
C.putchar(rest_first.pick(1))
C.putchar(rest_first.pick(1, 2))
C.putchar(10)
