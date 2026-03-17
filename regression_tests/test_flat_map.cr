# Test flat_map with nested arrays (exercises union yield through block-to-proc)
nested = [[1, 2], [3, 4], [5]]
flat = nested.flat_map { |a| a }

if flat.size == 5
  puts "PASS: flat_map size"
else
  puts "FAIL: flat_map size expected 5 got #{flat.size}"
end

if flat == [1, 2, 3, 4, 5]
  puts "PASS: flat_map values"
else
  puts "FAIL: flat_map values"
end

# flat_map with transform
result = [1, 2, 3].flat_map { |x| [x, x * 10] }
if result.size == 6
  puts "PASS: flat_map transform size"
else
  puts "FAIL: flat_map transform size expected 6 got #{result.size}"
end
