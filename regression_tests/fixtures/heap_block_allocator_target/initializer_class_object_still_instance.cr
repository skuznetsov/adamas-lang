lib C
  fun putchar(value : Int32) : Int32
end
class ClassValueInitializerToken
  def initialize(@code : Int32 = 65, &@callback : ClassValueInitializerToken -> Nil)
    ClassValueInitializerToken
  end
  def code : Int32
    @code
  end
end
def wrapper : ClassValueInitializerToken
  ClassValueInitializerToken.new { |item| nil }
end
C.putchar(wrapper.code)
