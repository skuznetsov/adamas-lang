lib Native
  fun putchar(value : Int32) : Int32
end
def choose(seed, *, a, **options)
  65
end
def choose(seed, *, b, **options)
  80
end
def forward(seed, **options)
  Native.putchar(choose(seed, **options, a: 1))
  Native.putchar(choose(seed, **options, b: 2))
  Native.putchar(10)
end
forward(0)
forward(0, item: 1)
