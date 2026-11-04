def relay(&callback : Int32.class -> Int64)
  restored = Box(typeof(callback)).unbox(Box.box(callback))
  restored.call(7)
end

abort "wrong result" unless relay { |type| 2147483655_i64 } == 2147483655_i64
