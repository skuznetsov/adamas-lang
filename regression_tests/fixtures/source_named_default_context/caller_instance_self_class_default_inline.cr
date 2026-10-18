@[Link("c")]
lib SourceDefaultInlineClassSelfC
  fun putchar(value : Int32) : Int32
end

class SourceDefaultInlineClassSelfBlock
  def self.visit
    yield
  end
end

class SourceDefaultInlineClassSelfCallee
  def self.source_code : Int32
    66
  end

  def source_code : Int32
    88
  end

  def self.emit(*, marker : Int32, value : Int32 = self.source_code) : Int32
    SourceDefaultInlineClassSelfC.putchar(value)
  end
end

class SourceDefaultInlineClassSelfCaller
  def run : Int32
    SourceDefaultInlineClassSelfBlock.visit do
      SourceDefaultInlineClassSelfCallee.emit(marker: 1)
    end
  end

  def source_code : Int32
    88
  end
end

SourceDefaultInlineClassSelfCaller.new.run
SourceDefaultInlineClassSelfC.putchar(10)
