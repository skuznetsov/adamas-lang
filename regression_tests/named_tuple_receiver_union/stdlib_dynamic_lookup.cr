def row(flag : Bool)
  if flag
    {value: 17, active: false}
  else
    {state: true, value: "second"}
  end
end

def lookup(row : NamedTuple, key : String)
  row[key]?
end

first = row(true)
second = row(false)
a = lookup(first, "value")
b = lookup(second, "value")
c = lookup(first, "active")
d = lookup(second, "state")
exit 1 unless a.is_a?(Int32) && a == 17
exit 2 unless b.is_a?(String) && b == "second"
exit 3 unless c.is_a?(Bool) && !c
exit 4 unless d.is_a?(Bool) && d
exit 5 unless lookup(first, "state").nil?
exit 6 unless lookup(second, "active").nil?
puts "named tuple union lookup"
