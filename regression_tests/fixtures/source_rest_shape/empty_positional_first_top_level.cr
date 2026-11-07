lib Native
  fun putchar(value : Int32) : Int32
end
def choose(seed, options : NamedTuple)
  80
end
def choose(seed, **options)
  65
end
def forward(seed, **options)
  Native.putchar(choose(seed, options))
  Native.putchar(choose(seed, **options))
  Native.putchar(10)
end
forward(0)
