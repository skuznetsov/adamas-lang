lib RawCallbackCallsiteRuntime
  fun putchar(value : Int32) : Int32
end

require "./raw_callback_callsite_helper"

RawCallbackCallsiteSource.emit(65_i32, true) do |value|
  RawCallbackCallsiteRuntime.putchar(value)
end

RawCallbackCallsiteSource.emit(use_seed: false, seed: 65_i32) do |value|
  RawCallbackCallsiteRuntime.putchar(value)
end

RawCallbackCallsiteRuntime.putchar(10_i32)
