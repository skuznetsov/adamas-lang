span = Time::Span.new(seconds: 2, nanoseconds: 17)
range = (Time::Span.zero..nil)
clamped = span.clamp(range)
raise "Time::Span range constructor lost its inline begin value" unless clamped == span
puts "range_constructor_inline_field_ok"
