backtrace = Exception::CallStack.new([] of Void*).printable_backtrace
puts backtrace.empty? ? "empty-callstack" : "unexpected-callstack"
