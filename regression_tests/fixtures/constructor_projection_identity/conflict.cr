class ConstraintCarrier(T)
  def initialize(@value : T)
  end
end
class ConflictingAction(T)
  def initialize(@left : ConstraintCarrier(T), @right : ConstraintCarrier(T))
  end
end
ConflictingAction.new(ConstraintCarrier(Int32).new(1), ConstraintCarrier(Int64).new(2_i64))
