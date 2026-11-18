require "./routes"

struct LeftRoute
  def result(value : KindToken.class) : Int32
    65
  end

  def result(value : KindToken) : Bool
    true
  end
end

struct RightRoute
  def result(value : KindToken) : Bool
    false
  end

  def result(value : KindToken.class) : Int32
    67
  end
end

def report(value : Int32)
  RouteOutput.putchar(value)
end

def report(value : Bool)
  RouteOutput.putchar(value ? 66 : 68)
end

report(route(true).result(KindToken))
report(route(true).result(KindToken.new))
report(route(false).result(KindToken.new))
report(route(false).result(KindToken))
RouteOutput.putchar(10)
