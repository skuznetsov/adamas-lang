h = {} of {String, String, Int32?, Bool} => String?
key = {"Range(Int32, Int32)", "[]", 1, false}

h[key] = "ok"

puts h.has_key?(key)
puts h[key] || "nil"
