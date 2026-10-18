@[Link("c")]
lib LogEnumByteOracleC
  fun putchar(value : Int32) : Int32
end

enum SeverityProbe
  Info
  Warn
end

class SeveritySelectorProbe
  def self.choose(value : SeverityProbe, *, marker : Int32) : Int32
    LogEnumByteOracleC.putchar(69) # E: nominal enum overload
  end

  def self.choose(value : Int32, *, marker : Int32) : Int32
    LogEnumByteOracleC.putchar(73) # I: raw Int32 overload
  end
end

struct NamedEntryProbe
  def initialize(@severity : SeverityProbe, *, @timestamp : Int32)
    LogEnumByteOracleC.putchar(78) # N: enum-shaped initializer
  end
end

stored = SeverityProbe::Warn
SeveritySelectorProbe.choose(SeverityProbe::Info, marker: 1)
SeveritySelectorProbe.choose(stored, marker: 2)
SeveritySelectorProbe.choose(value: SeverityProbe::Info, marker: 3)
SeveritySelectorProbe.choose(value: stored, marker: 4)
SeveritySelectorProbe.choose(7, marker: 5)
SeveritySelectorProbe.choose(value: 7, marker: 6)
SeveritySelectorProbe.choose(SeverityProbe::Info.value, marker: 7)
NamedEntryProbe.new(SeverityProbe::Info, timestamp: 10)
NamedEntryProbe.new(stored, timestamp: 11)
LogEnumByteOracleC.putchar(10)
