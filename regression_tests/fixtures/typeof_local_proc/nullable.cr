def relay(value : Int32, &callback : Int32 -> Int64?)
  thunk = Proc(Void*, Int64?).new do |raw|
    restored = Box(typeof(callback)).unbox(raw)
    restored.call(value)
  end
  thunk.call(Box.box(callback))
end

abort "wrong result" unless relay(7) { |value| value == 7 ? 2147483655_i64 : nil } == 2147483655_i64
abort "wrong nil" unless relay(8) { |value| value == 7 ? 2147483655_i64 : nil }.nil?
