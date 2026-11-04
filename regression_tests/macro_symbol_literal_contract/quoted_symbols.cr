def bool_field(value : Bool)
  value ? 1 : 2
end

def count_fields(row)
  count = 0
  row.each do |key, value|
    count += bool_field(value)
  end
  count
end

def named_argument(value : String)
  value
end

# Compare interned identities to isolate literal lowering from method dispatch.
def symbol_id(value : Symbol)
  value.unsafe_as(Int32)
end

exit 1 unless count_fields({before: true, "basic.nack": false, after: true}) == 4
exit 2 unless count_fields({"connection.blocked": true, "has space": false}) == 3
exit 3 unless count_fields({before: false, "basic.nack": true, after: false}) == 5
exit 4 unless symbol_id({{ "basic.nack".id.symbolize }}) == symbol_id(:"basic.nack")
exit 5 unless symbol_id({{ "a\"b\\c\n".id.symbolize }}) == symbol_id(:"a\x22b\x5cc\x0a")
exit 6 unless symbol_id(:"#{literal}") == symbol_id(:"\x23{literal}")
exit 7 if symbol_id(:":leading") == symbol_id(:leading)
exit 8 unless symbol_id({{ "^".id.symbolize }}) == symbol_id(:^)
exit 9 unless named_argument(value:"value") == "value"
puts "quoted symbols and named tuple iteration"
