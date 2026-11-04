class SmallKey
  def key : Int32
    17
  end
end

class WideKey
  def key : UInt64
    2147483649_u64
  end
end

def bare(receiver : SmallKey | WideKey)
  receiver.key
end

def explicit(receiver : SmallKey | WideKey)
  receiver.key()
end

receiver = ARGV.empty? ? SmallKey.new : WideKey.new
puts bare(receiver)
puts explicit(receiver)
