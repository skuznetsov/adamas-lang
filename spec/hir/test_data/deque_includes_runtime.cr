deque = Deque(Int32).new
deque.push(7)

if deque.includes?(7) && !deque.includes?(8)
  puts "generated-deque-includes-ok"
else
  puts "generated-deque-includes-wrong"
end
