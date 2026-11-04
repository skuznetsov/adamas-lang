class KnownKey
  def key : UInt64
    19_u64
  end
end

class UnavailableKey
  def key(other : Bool)
    7_u64
  end
end

def dispatch(receiver : KnownKey | UnavailableKey)
  receiver.key()
end

receiver = ARGV.empty? ? KnownKey.new : UnavailableKey.new
puts dispatch(receiver)
