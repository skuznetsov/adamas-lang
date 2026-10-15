lib C
  fun exit(status : Int32) : NoReturn
end
fun __crystal_raise_overflow : NoReturn
  C.exit(97)
end

alias PositionedMetric = NamedTuple(other: UInt8, value: Int32) | NamedTuple(value: Int64, other: UInt16)
alias OptionalMetric = NamedTuple(value: Int32) | NamedTuple(value: UInt16, label: Int32 | Int64)
alias NestedMetric = NamedTuple(value: Int32) | NamedTuple(value: UInt16, labels: NamedTuple(vhost: Int32) | NamedTuple(queue: Int64))

def read_symbol(metric : PositionedMetric) : Int64
  metric[:value].to_i64
end

def read_string(metric : PositionedMetric) : Int64
  metric.[]("value").to_i64
end

def read_optional(metric : OptionalMetric) : Int64
  if label = metric[:label]?
    label.to_i64
  else
    41_i64
  end
end

def missing_optional(metric : PositionedMetric) : Bool
  metric["absent"]?.nil?
end

def nested_optional(metric : NestedMetric) : Int32
  if labels = metric.[]?(:labels)
    if vhost = labels[:vhost]?
      vhost
    else
      43
    end
  else
    41
  end
end

C.exit(1) unless read_symbol({other: 3_u8, value: 42}) == 42_i64
C.exit(2) unless read_symbol({value: 0x1_0000_002a_i64, other: 4_u16}) == 0x1_0000_002a_i64
C.exit(3) unless read_string({other: 3_u8, value: 42}) == 42_i64
C.exit(4) unless read_string({value: 0x1_0000_002a_i64, other: 4_u16}) == 0x1_0000_002a_i64
C.exit(5) unless read_optional({value: 7}) == 41_i64
C.exit(6) unless read_optional({value: 8_u16, label: 42}) == 42_i64
C.exit(7) unless read_optional({value: 8_u16, label: 0x1_0000_002b_i64}) == 0x1_0000_002b_i64
C.exit(8) unless missing_optional({other: 3_u8, value: 42})
C.exit(9) unless missing_optional({value: 42_i64, other: 4_u16})
C.exit(10) unless nested_optional({value: 7}) == 41
C.exit(11) unless nested_optional({value: 8_u16, labels: {vhost: 42}}) == 42
C.exit(12) unless nested_optional({value: 8_u16, labels: {queue: 42_i64}}) == 43
C.exit(13) unless ({flag: false}[:flag]?) == false
C.exit(14) unless ({value: 42}[:missing]?).nil?

alias ReorderedMetric = NamedTuple(label: Int32 | Int64, value: UInt16)
alias CompatibleMetric = NamedTuple(a: Int32 | Int64, b: Int32) | NamedTuple(a: Int32, b: Int32 | Int64)

def read_reordered(metric : ReorderedMetric) : Int64
  metric[:label].to_i64 + metric[:value].to_i64
end

def read_compatible(metric : CompatibleMetric) : Int64
  metric[:a].to_i64 + metric[:b].to_i64
end

C.exit(15) unless read_reordered({value: 8_u16, label: 42}) == 50_i64
C.exit(16) unless read_reordered({value: 8_u16, label: 0x1_0000_002a_i64}) == 0x1_0000_0032_i64
C.exit(17) unless read_compatible({a: 41, b: 1}) == 42_i64
C.exit(18) unless read_optional({value: 8_u16, label: 0}) == 0_i64

alias OptionalFlag = NamedTuple(flag: Bool) | NamedTuple(absent: Int32)
def read_union_flag(value : OptionalFlag) : Bool?
  value[:flag]?
end
flag = read_union_flag({flag: false})
C.exit(19) if flag
C.exit(20) if flag.nil?
C.exit(21) unless read_union_flag({flag: true})
C.exit(22) unless read_union_flag({absent: 42}).nil?
C.exit(0)
