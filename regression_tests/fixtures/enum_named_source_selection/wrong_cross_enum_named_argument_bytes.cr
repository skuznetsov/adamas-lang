@[Link("c")]
lib LogEnumByteOracleC
  fun putchar(value : Int32) : Int32
end

enum SeverityProbe
  Info
end

enum OtherSeverityProbe
  Alert
end

struct EnumOnlyEntryProbe
  def initialize(@severity : SeverityProbe, *, @timestamp : Int32)
    LogEnumByteOracleC.putchar(69)
  end
end

# A different nominal enum must not satisfy this enum-only formal.
EnumOnlyEntryProbe.new(OtherSeverityProbe::Alert, timestamp: 10)
