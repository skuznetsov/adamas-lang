def stringify_matches(actual : String, expected : String) : Bool
  actual == expected
end

macro check_stringify_argument(value)
  puts stringify_matches({{value.stringify}}, {{value}}.inspect)
end

check_stringify_argument("plain argument")
check_stringify_argument("")
check_stringify_argument("quoted: \"value\"")
check_stringify_argument("backslash \\ path")
check_stringify_argument("line 1\nline 2")
check_stringify_argument("literal \#{name}")
check_stringify_argument("literal \\\#{name}")
check_stringify_argument("λ雪🙂")
