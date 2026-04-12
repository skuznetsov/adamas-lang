# Reaches Fiber.yield -> EventLoop#sleep(0) -> Polling::Event + Timers(Crystal::EventLoop::Polling::Event).
# Compiler regression: unqualified generic owner `Timers(...)` must resolve to the registered template
# `Crystal::EventLoop::Timers` so Timers#add/delete/next_ready? are lowered (no LLVM abort stub).
# Baseline (broken): stderr contained STUB CALLED: ...Timers$...$Hadd..., exit 134.
# After fix: verify with `--emit llvm-ir` that `define i1 @Timers$...$Hadd` exists and no ABORT stub for Timers.
# Runtime may still fail later in the event loop (e.g. Kqueue); that is a separate issue from Timers lowering.
# EXPECT: before_yield
puts "before_yield"
Fiber.yield
puts "after_yield"
