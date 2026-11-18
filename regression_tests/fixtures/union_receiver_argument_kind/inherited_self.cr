require "./routes"

abstract struct OwnerRoute
  def emit(value : KindToken.class) : Int32
    marker
  end

  def emit(value : KindToken) : Int32
    70
  end

  def marker : Int32
    88
  end
end

struct LocalRoute < OwnerRoute
  def marker : Int32
    69
  end
end

def local_route(left : Bool) : LocalRoute | LeftRoute
  left ? LeftRoute.new : LocalRoute.new
end

RouteOutput.putchar(local_route(false).emit(KindToken))
RouteOutput.putchar(local_route(false).emit(KindToken.new))
RouteOutput.putchar(local_route(true).emit(KindToken))
RouteOutput.putchar(10)
