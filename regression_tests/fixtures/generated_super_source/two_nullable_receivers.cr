lib LibC
  fun putchar(value : Int32) : Int32
end

abstract struct Enum
  def self.make(value : Int32) : self?
    return nil if value == 0
    new(value)
  end

  def self.build(value : Int32) : self
    make(value) || new(value)
  end
end

enum SelfFirst
  Answer = 65
  def self.build(value : Int32) : self
    super(value)
  end
end

enum SelfSecond
  Answer = 66
  def self.build(value : Int32) : self
    super(value)
  end
end

def mark_first(value : SelfFirst) : Int32
  value.value
end

def mark_second(value : SelfSecond) : Int32
  value.value
end

LibC.putchar(mark_first(SelfFirst.build(65)))
LibC.putchar(mark_second(SelfSecond.build(66)))
LibC.putchar(10)
