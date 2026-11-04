class BaseKey
  def key : UInt64
    2147483649_u64
  end
end

class WideKey < BaseKey
  def key(other : Bool)
    7_u64
  end
end

class SmallKey
  def key : UInt64
    17_u64
  end
end

def read_key(receiver : SmallKey | WideKey)
  receiver.key
end

receiver = ARGV.empty? ? SmallKey.new : WideKey.new
puts read_key(receiver)
