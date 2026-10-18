@[Link("c")]
lib SourceDefaultClassSelfC
  fun putchar(value : Int32) : Int32
end

class SourceDefaultClassSelfCallee
  def self.source_code : Int32
    66
  end

  def source_code : Int32
    88
  end

  def self.emit(*, marker : Int32, value : Int32 = self.source_code) : Int32
    SourceDefaultClassSelfC.putchar(value)
  end
end

class SourceDefaultClassSelfCaller
  def run : Int32
    SourceDefaultClassSelfCallee.emit(marker: 1)
  end

  def source_code : Int32
    88
  end
end

SourceDefaultClassSelfCaller.new.run
SourceDefaultClassSelfC.putchar(10)
