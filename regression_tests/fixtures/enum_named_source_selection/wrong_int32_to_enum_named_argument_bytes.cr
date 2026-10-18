@[Link("c")]
lib LogEnumByteOracleC
  fun putchar(value : Int32) : Int32
end

enum SeverityProbe
  Info
end

struct EnumOnlyEntryProbe
  def initialize(@severity : SeverityProbe, *, @timestamp : Int32)
    LogEnumByteOracleC.putchar(69)
  end
end

# A plain Int32 must not satisfy an enum-only formal.
EnumOnlyEntryProbe.new(7, timestamp: 10)
