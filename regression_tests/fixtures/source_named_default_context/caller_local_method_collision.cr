@[Link("c")]
lib SourceDefaultCallerLocalC
  fun putchar(value : Int32) : Int32
end

class SourceDefaultMethodCollisionCallee
  def self.fallback : Int32
    65
  end

  def self.emit(*, marker : Int32, value : Int32 = fallback) : Int32
    SourceDefaultCallerLocalC.putchar(value)
  end
end

class SourceDefaultMethodCollisionCaller
  def run : Int32
    fallback = 88
    SourceDefaultMethodCollisionCallee.emit(marker: 1)
  end
end

SourceDefaultMethodCollisionCaller.new.run
SourceDefaultCallerLocalC.putchar(10)
