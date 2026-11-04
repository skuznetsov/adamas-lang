lib LibC
  fun exit(status : Int32) : NoReturn
end

class Walker(T)
  def self.walk(depth : Int32, callback : Proc(Int32, T)) : T
    if depth == 0
      callback.call(5)
    else
      walk(depth &- 1, callback)
    end
  end

  def self.walk(depth : Int32, &block : Int32 -> T) : T
    block.call(depth &+ 100)
  end
end

def count_down(depth : Int32) : Int32
  if depth == 0
    17
  else
    count_down(depth &- 1)
  end
end

def count_down(depth) : Int32
  99
end

callback = ->(value : Int32) { value &* 2 }
LibC.exit(1) unless Walker(Int32).walk(3, callback) == 10
LibC.exit(2) unless Walker(Int32).walk(3, &callback) == 206
LibC.exit(3) unless Walker(Int32).walk(3) { |value| value } == 103
LibC.exit(4) unless count_down(3) == 17
LibC.exit(0)
