def stringify_matches(actual : String, expected : String) : Bool
  actual == expected
end

macro direct_stringify_cases
  puts stringify_matches({{"plain".stringify}}, "plain".inspect)
  puts stringify_matches({{"".stringify}}, "".inspect)
  puts stringify_matches({{"quoted: \"value\"".stringify}}, "quoted: \"value\"".inspect)
  puts stringify_matches({{"backslash \\ path".stringify}}, "backslash \\ path".inspect)
  puts stringify_matches({{"line 1\nline 2".stringify}}, "line 1\nline 2".inspect)
  puts stringify_matches({{"literal \#{name}".stringify}}, "literal \#{name}".inspect)
  puts stringify_matches({{"λ雪🙂".stringify}}, "λ雪🙂".inspect)
  assigned = {{"assigned expression".stringify}}
  puts stringify_matches(assigned, "assigned expression".inspect)
end

direct_stringify_cases
