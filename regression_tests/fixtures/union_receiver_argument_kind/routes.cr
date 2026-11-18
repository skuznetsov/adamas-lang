@[Link("c")]
lib RouteOutput
  fun putchar(value : Int32) : Int32
end

class KindToken
end

struct LeftRoute
  def emit(value : KindToken.class) : Int32
    65
  end

  def emit(value : KindToken) : Int32
    66
  end
end

struct RightRoute
  def emit(value : KindToken) : Int32
    68
  end

  def emit(value : KindToken.class) : Int32
    67
  end
end

def route(left : Bool) : LeftRoute | RightRoute
  left ? LeftRoute.new : RightRoute.new
end
