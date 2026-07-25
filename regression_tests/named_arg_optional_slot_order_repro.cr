# Named arguments bind by external name, independently of declaration order
# and omitted earlier optional parameters.

class NamedSlotProbe
  getter first : Int32
  getter second : Int32
  getter third : Int32
  getter fourth : Int32

  def initialize(
    @first : Int32 = 1,
    @second : Int32 = 2,
    @third : Int32 = 3,
    @fourth : Int32 = 4,
  )
  end
end

def named_slot_value(
  first : Int32 = 1,
  second : Int32 = 2,
  third : Int32 = 3,
  fourth : Int32 = 4,
) : Int32
  first * 1_000_000 + second * 10_000 + third * 100 + fourth
end

exit 9 unless named_slot_value(third: 30) == 1_023_004
exit 10 unless named_slot_value(fourth: 40, second: 20) == 1_200_340

only_third = NamedSlotProbe.new(third: 30)
exit 1 unless only_third.first == 1
exit 2 unless only_third.second == 2
exit 3 unless only_third.third == 30
exit 4 unless only_third.fourth == 4

reordered = NamedSlotProbe.new(fourth: 40, second: 20)
exit 5 unless reordered.first == 1
exit 6 unless reordered.second == 20
exit 7 unless reordered.third == 3
exit 8 unless reordered.fourth == 40

exit 0
