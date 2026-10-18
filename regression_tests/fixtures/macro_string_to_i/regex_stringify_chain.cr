lib LibC
  fun putchar(c : Int32) : Int32
end

macro widths(from, to)
  {% n = from.stringify.gsub(/^.*?(\d+)$/, "\\1").to_i %}
  {% to_n = to.stringify.gsub(/^.*?(\d+)$/, "\\1").to_i %}
  LibC.putchar({{n - 63}})
  LibC.putchar({{to_n + 2}})
end
widths(Int128, Float64)
LibC.putchar(10)
