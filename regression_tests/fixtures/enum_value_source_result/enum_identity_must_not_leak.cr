lib C
  fun putchar(c : Int32) : Int32
end

# Mirror the stock Enum#value source body. These calls are made from another
# Enum instance method through a bare identifier, not through `obj.value`.
abstract struct Enum
  def value : Int
    previous_def
  end
end

def select_enum(value : EnumIdentityGuard) : Int32
  0
end

enum EnumIdentityGuard
  Answer = 4

  def pass_value_as_enum : Int32
    select_enum(value)
  end
end

EnumIdentityGuard::Answer.pass_value_as_enum
C.putchar(10)
