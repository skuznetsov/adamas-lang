@[Link("c")]
lib SourceDefaultInheritedC
  fun putchar(value : Int32) : Int32
end
class SourceDefaultInheritedBase
  def self.source_code : Int32
    65
  end
  def self.emit(*, marker : Int32, value : Int32 = self.source_code) : Int32
    value
  end
end
class SourceDefaultInheritedChild < SourceDefaultInheritedBase
  def self.source_code : Int32
    66
  end
end
class SourceDefaultInheritedCaller
  def source_code : Int32
    88
  end
  def run : Int32
    SourceDefaultInheritedC.putchar(SourceDefaultInheritedChild.emit(marker: 1))
  end
end
SourceDefaultInheritedCaller.new.run
SourceDefaultInheritedC.putchar(10)
