# Reaches Fiber.yield -> EventLoop#sleep(0) -> Polling::Event + Timers (may hit stub after Event init).
# EXPECT: before_yield
puts "before_yield"
Fiber.yield
puts "after_yield"
