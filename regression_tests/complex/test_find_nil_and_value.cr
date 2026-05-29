# EXPECT: find_nil_and_value_ok

def pick(args : Array(String))
  args.find { |arg| !arg.starts_with?("-") }
end

value = pick(["--release", "src/adamas.cr"])
none = pick(["--release", "--no-debug"])

ok = value == "src/adamas.cr" && none.nil?
puts(ok ? "find_nil_and_value_ok" : "find_nil_and_value_bad")
