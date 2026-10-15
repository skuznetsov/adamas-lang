lib C
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  C.exit(97)
end

class BlockResultOwner(T, N)
  def check(&block : T, T -> U) : Int32 forall U
    {% unless U == Int32 && T == Int32 && N == 2 %}
      {% raise "block result or receiver binding was overwritten" %}
    {% end %}
    41
  end
end

class ShadowedBlockOwner(T, U)
  def check(&block : T -> U) : Int32 forall U
    {% unless U == Int64 && T == Int32 %}
      {% raise "method forall lost to owner U" %}
    {% end %}
    42
  end
end

class ConcreteBlockOwner(T, U)
  def check(&block : T -> Int32) : Int32
    {% unless U == UInt8 && T == Int32 %}
      {% raise "concrete block annotation rebound the owner U" %}
    {% end %}
    43
  end
end

class LiteralArgumentOwner(N)
  def check : Int32
    {% unless N.class_name == "NumberLiteral" && N == 2 && N != 3 && N + 1 == 3 %}
      {% raise "numeric generic argument lost its literal kind or value" %}
    {% end %}
    44
  end
end

class TypedLiteralOwner(N)
  def check : Int32
    {% unless N.class_name == "NumberLiteral" && N == 2_i64 && N != 2_i32 %}
      {% raise "numeric generic argument lost its integer kind" %}
    {% end %}
    45
  end
end

C.exit(1) unless BlockResultOwner(Int32, 2).new.check { |left, right| 1 } == 41
C.exit(2) unless ShadowedBlockOwner(Int32, UInt8).new.check { |value| 1_i64 } == 42
C.exit(3) unless ConcreteBlockOwner(Int32, UInt8).new.check { |value| 1 } == 43
C.exit(4) unless LiteralArgumentOwner(2).new.check == 44
C.exit(5) unless LiteralArgumentOwner(0x2).new.check == 44
C.exit(6) unless TypedLiteralOwner(2_i64).new.check == 45
