lib C
  fun putchar(value : Int32) : Int32
end
class RestGuard
  def self.call(value : Int32, **options)
    65
  end
end
C.putchar(RestGuard.call(Int32, tag: 1))
