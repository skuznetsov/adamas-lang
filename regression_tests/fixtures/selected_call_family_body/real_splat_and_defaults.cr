lib C
  fun exit(status : Int32) : NoReturn
end

class FamilyOwner(T)
  def self.choose(*items)
    23
  end

  def self.choose(item : Int64)
    id(item, false)
  end

  private def self.id(item : Int64, other : Bool)
    other ? nil : item
  end
end

class DefaultOwner(T)
  def self.choose(item : Int32 = 17)
    item &+ 1
  end

  def self.choose(item : Int64)
    item &+ 2_i64
  end
end

case value = FamilyOwner(Nil).choose(42_i64)
when Int64
  C.exit(11) unless value == 42_i64
else
  C.exit(12)
end
C.exit(13) unless FamilyOwner(Nil).choose() == 23
C.exit(14) unless FamilyOwner(Nil).choose(7_i32) == 23
C.exit(15) unless DefaultOwner(Nil).choose() == 18
C.exit(16) unless DefaultOwner(Nil).choose(40_i64) == 42_i64
C.exit(0)
