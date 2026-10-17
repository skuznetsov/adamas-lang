@[Link("c")]
lib NamedFFIProbe
  fun parse = strtol(input : UInt8*, endptr : UInt8**, base : Int32) : Int64
  fun putchar(value : Int32) : Int32
end

# Both source call paths must apply String#to_unsafe after tuple expansion.
NamedFFIProbe.putchar(NamedFFIProbe.parse(*{"66!", nil, 10}).to_i32)
NamedFFIProbe.putchar(10)
NamedFFIProbe.putchar(NamedFFIProbe.parse(*{"67!"}, base: 10, endptr: nil).to_i32)
NamedFFIProbe.putchar(10)

def tuple_input
  NamedFFIProbe.putchar(65)
  {"68!"}
end

NamedFFIProbe.putchar(NamedFFIProbe.parse(*tuple_input, base: 10, endptr: nil).to_i32)
NamedFFIProbe.putchar(10)
