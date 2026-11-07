lib Native
  fun putchar(value : Int32) : Int32
end
def choose(seed, options : NamedTuple, &)
  yield
  80
end
def choose(seed, **options, &)
  yield
  65
end
def forward(seed, **options)
  Native.putchar(choose(seed, options) { Native.putchar(66) })
  Native.putchar(choose(seed, **options) { Native.putchar(66) })
  Native.putchar(10)
end
forward(0, item: 1)
