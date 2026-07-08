# Regression test: adjacent string literals must concatenate, matching Crystal.
#   "a" "b"             (same line, whitespace-separated) -> "ab"
#   "a" \<newline> "b"  (backslash line-continuation)     -> "ab"
#   "a"<newline>"b"     (bare newline = statement boundary) -> stays SEPARATE
# The concatenation composes with interpolation, so a mixed run like
#   "x=#{v}\n" \
#   "y\n"
# merges into a single interpolated literal. The compiler's own codegen
# synthesizers are full of such backslash-continued multi-line strings
# (e.g. Object#==(T) -> a 4-line `define ... { ret 0 }`); before this fix the
# parser kept only the FIRST piece, truncating every generated string and
# producing undefined symbols (e.g. `@Object#==$Int32`) during self-host.
# EXPECT: adjacent_string_concat_ok

# same-line adjacency
a = "aaa\n" "bbb\n" "ccc\n"
# backslash line-continuation
b = "aaa\n" \
    "bbb\n"
# bare newline: separate statements, `c` holds only the first literal
c = "aaa\n"
"bbb\n"
# mixed interpolation + plain, backslash-continued (real synthesizer shape)
v = 7
d = "x=#{v}\n" \
    "define #{v}\n" \
    "}\n"

ok = true
ok = false unless a.bytesize == 12
ok = false unless b.bytesize == 8
ok = false unless c.bytesize == 4
ok = false unless d.bytesize == 15
ok = false unless d == "x=7\ndefine 7\n}\n"

if ok
  puts "adjacent_string_concat_ok"
else
  puts "FAIL a=#{a.bytesize} b=#{b.bytesize} c=#{c.bytesize} d=#{d.bytesize} d=#{d.inspect}"
end
