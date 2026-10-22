lib LibC
  fun putchar(value : Int32) : Int32
end

# Parsing a hash in a lazy body must retain both entries and its postfix.
# Keeping it lazy avoids making this parser guard depend on Hash runtime code.
def unused_hash_literal_postfix
  {1 => 2, 3 => 4}[1]
end

LibC.putchar({65, 66}[0])
LibC.putchar({value: 66}[:value])
LibC.putchar({first: {67, 68}, last: 69}[:first][0])
