# A' BEHAVIOR reducer: inline Array(C) storage (gate ADAMAS_INLINE_VALUE_ARRAY_STORAGE).
#
# Exercises the whole Array(C) storage family for a 12-byte leaf-POD struct (stride
# 12 != pointer 8, so any stride mismatch corrupts): push + grow/realloc, indexed
# read (carrier copy), delete_at / shift / insert / concat (memmove/clear at inline
# stride), and copy-on-load NO-ALIAS (a loaded value is an independent heap carrier,
# so overwriting the slot does not change the previously-loaded value).
#
# Prints one RESULT line; the companion script asserts it equals the gate-OFF
# (legacy) result — inline storage must be behavior-identical, just a different ABI.
struct V3
  getter a : Int32
  getter b : Int32
  getter c : Int32

  def initialize(@a : Int32, @b : Int32, @c : Int32)
  end
end

# push past initial capacity → grow/realloc must preserve every element's 12 bytes.
arr = [] of V3
i = 0
while i < 10
  arr << V3.new(i, i * 10, i * 100)
  i += 1
end
grow_sum = 0
j = 0
while j < arr.size
  v = arr[j]
  grow_sum += v.a + v.b + v.c
  j += 1
end

# copy-on-load no-alias: v0 is a carrier copy of slot 0; overwriting slot 0 must NOT
# change v0.
v0 = arr[0]
arr[0] = V3.new(777, 888, 999)
alias_ok = (v0.a == 0 && v0.b == 0 && v0.c == 0) && (arr[0].a == 777)

# mutation family at inline stride.
arr.delete_at(3)
arr.insert(1, V3.new(5, 5, 5))
arr.shift
other = [] of V3
other << V3.new(4, 4, 4)
arr.concat(other)
mut_sum = 0
k = 0
while k < arr.size
  w = arr[k]
  mut_sum += w.a + w.b + w.c
  k += 1
end

STDERR.puts "RESULT grow_sum=#{grow_sum} alias_ok=#{alias_ok} size=#{arr.size} mut_sum=#{mut_sum}"
STDOUT.flush
exit(0)
