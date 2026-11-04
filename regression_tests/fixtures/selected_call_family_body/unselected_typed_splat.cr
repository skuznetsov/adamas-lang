lib C
  fun exit(status : Int32) : NoReturn
end

class FamilyOwner(T)
  def self.choose(*items : Int32)
    missing_in_unselected_splat(items)
  end

  def self.choose(item : Int64)
    id(item, false)
  end

  private def self.id(item : Int64, other : Bool)
    other ? nil : item
  end
end

case value = FamilyOwner(Nil).choose(42_i64)
when Int64
  C.exit(value == 42_i64 ? 0 : 21)
else
  C.exit(22)
end
