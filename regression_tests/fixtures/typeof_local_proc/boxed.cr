def relay(&callback : Int32 -> Int64)
  thunk = Proc(Void*, Int64).new do |raw|
    restored = Box(typeof(callback)).unbox(raw)
    restored.call(7)
  end
  thunk.call(Box.box(callback))
end

abort "wrong result" unless relay { |value| 2147483648_i64 + value } == 2147483655_i64
