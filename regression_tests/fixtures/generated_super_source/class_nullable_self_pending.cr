lib LibC
  fun putchar(value : Int32) : Int32
end

class NullableSelfBase
  def self.make(flag : Bool) : self?
    flag ? new : nil
  end

  def self.build(flag : Bool) : self
    make(flag) || new
  end
end

class NullableSelfChild < NullableSelfBase
  def self.build(flag : Bool) : self
    super(flag)
  end
end

def report(value : NullableSelfChild) : Int32
  65
end

def report(value : NullableSelfBase) : Int32
  66
end

LibC.putchar(report(NullableSelfChild.build(true)))
LibC.putchar(report(NullableSelfChild.build(false)))
LibC.putchar(10)
