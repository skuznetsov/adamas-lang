lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

values = [] of Tuple(Bool, Bool, Bool)
values << {true, false, true}
values << {false, true, false}

first_pop = values.pop

values << {true, true, false}
second_pop = values.pop
third_pop = values.pop

all_non_nil = !first_pop.nil? && !second_pop.nil? && !third_pop.nil?
empty_after_pops = values.empty?

LibC.printf(
  "ADAMAS_ARRAY_TUPLE_POP_OK:non_nil=%d;empty=%d\n",
  all_non_nil ? 1 : 0,
  empty_after_pops ? 1 : 0
)
