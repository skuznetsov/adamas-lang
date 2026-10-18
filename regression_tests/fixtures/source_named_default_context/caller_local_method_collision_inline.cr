@[Link("c")]
lib SourceDefaultInlineCallerLocalC
  fun putchar(value : Int32) : Int32
end

class SourceDefaultInlineCallerLocalBlock
  def self.visit
    yield
  end
end

class SourceDefaultInlineCallerLocalCallee
  def self.fallback : Int32
    65
  end

  def self.emit(*, marker : Int32, value : Int32 = fallback) : Int32
    SourceDefaultInlineCallerLocalC.putchar(value)
  end
end

class SourceDefaultInlineCallerLocalCaller
  def self.run : Int32
    fallback = 88
    SourceDefaultInlineCallerLocalBlock.visit do
      SourceDefaultInlineCallerLocalCallee.emit(marker: 1)
    end
  end
end

SourceDefaultInlineCallerLocalCaller.run
SourceDefaultInlineCallerLocalC.putchar(10)
