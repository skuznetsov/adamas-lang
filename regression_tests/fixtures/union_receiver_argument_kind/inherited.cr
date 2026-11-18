require "./routes"

abstract struct ParentRoute
  def emit(value : KindToken) : Int32
    70
  end

  def emit(value : KindToken.class) : Int32
    69
  end
end

struct ChildRoute < ParentRoute
end

def inherited_route(left : Bool) : LeftRoute | ChildRoute
  left ? LeftRoute.new : ChildRoute.new
end

RouteOutput.putchar(inherited_route(false).emit(KindToken))
RouteOutput.putchar(inherited_route(false).emit(KindToken.new))
RouteOutput.putchar(inherited_route(true).emit(KindToken.new))
RouteOutput.putchar(inherited_route(true).emit(KindToken))
RouteOutput.putchar(10)
