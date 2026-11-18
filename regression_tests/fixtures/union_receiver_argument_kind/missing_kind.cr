require "./routes"

struct InstanceOnlyRoute
  def emit(value : KindToken) : Int32
    71
  end
end

def mixed_route(left : Bool) : LeftRoute | InstanceOnlyRoute
  left ? LeftRoute.new : InstanceOnlyRoute.new
end

mixed_route(true).emit(KindToken)
