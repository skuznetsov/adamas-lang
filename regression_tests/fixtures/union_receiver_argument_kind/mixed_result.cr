require "./routes"

struct LeftRoute
  def data(value : KindToken.class) : Int32
    65
  end

  def data(value : KindToken) : Bool
    true
  end
end

struct RightRoute
  def data(value : KindToken) : Int32
    68
  end

  def data(value : KindToken.class) : Bool
    false
  end
end

def display(value : Int32 | Bool)
  if value.is_a?(Int32)
    RouteOutput.putchar(value)
  else
    RouteOutput.putchar(value ? 66 : 67)
  end
end

display(route(true).data(KindToken))
display(route(true).data(KindToken.new))
display(route(false).data(KindToken))
display(route(false).data(KindToken.new))
RouteOutput.putchar(10)
