require "./helpers/macros"
def consume_int(value : Int32) : Int32
  value
end
property next : ::Int32 = consume_int("bad"), "next", "::Int32"
