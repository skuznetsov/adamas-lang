class Walker(T)
  def self.walk(depth : Int32, callback : Proc(Int32, T)) : T
    callback.call(depth)
  end

  def self.walk(depth : Int32, &block : Int32 -> T) : T
    block.call(depth)
  end
end

Walker(Int32).walk(3, ->{ true })
