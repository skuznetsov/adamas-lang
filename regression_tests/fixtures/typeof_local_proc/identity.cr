lib LibC
  fun exit(status : Int32) : NoReturn
end

class Identity(T)
  def self.echo(value : T) : T
    value
  end
end

def relay(&callback : Int32 -> Int64)
  thunk = ->(arg : Proc(Int32, Int64)) do
    restored = Identity(typeof(callback)).echo(arg)
    restored.call(7)
  end
  thunk.call(callback)
end

LibC.exit(1) unless relay { |value| value == 7 ? 2147483655_i64 : 0_i64 } == 2147483655_i64
LibC.exit(0)
