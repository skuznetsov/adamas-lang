lib Native
  fun putchar(value : Int32) : Int32
end
class SourceOwner
def self.choose(seed, options : NamedTuple)
  80
end
def self.choose(seed, **options)
  65
end
def self.forward(seed, **options)
  Native.putchar(choose(seed, **options))
  Native.putchar(choose(seed, options))
  Native.putchar(10)
end
end
SourceOwner.forward(0)
