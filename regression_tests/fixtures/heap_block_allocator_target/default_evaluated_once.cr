lib C
  fun putchar(value : Int32) : Int32
end
class DefaultOnceToken
  @@evaluations = 0
  def self.default_code : Int32
    @@evaluations = @@evaluations &+ 1
    65
  end
  def self.evaluations : Int32
    @@evaluations
  end
  def initialize(@code : Int32 = DefaultOnceToken.default_code, &@callback : DefaultOnceToken -> Nil)
    nil
  end
  def code : Int32
    @code
  end
end
token = DefaultOnceToken.new { |item| nil }
C.putchar(token.code)
C.putchar(64 &+ DefaultOnceToken.evaluations)
