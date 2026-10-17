macro capture_empty(**extras)
  puts {{ extras.size }}
  puts {{ extras.empty? }}
end

macro capture_one(**extras)
  puts {{ extras.size }}
  puts {{ extras[:alpha] }}
end

macro capture_two(**extras)
  puts {{ extras.size }}
  puts {{ extras[:alpha] }}
  puts {{ extras[:beta] }}
end

macro capture_with_label(label, **extras)
  puts {{ label }}
  puts {{ extras.size }}
  puts {{ extras[:alpha] }}
end

capture_empty
capture_one(alpha: 11)
capture_two(alpha: 13, beta: 17)
capture_with_label(label: 23, alpha: 29)
capture_one(alpha: 37)
capture_empty
capture_one(alpha: 41)
