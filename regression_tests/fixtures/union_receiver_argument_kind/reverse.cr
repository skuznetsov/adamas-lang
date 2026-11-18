require "./routes"

type = KindToken
value = KindToken.new
RouteOutput.putchar(route(false).emit(value))
RouteOutput.putchar(route(false).emit(type))
RouteOutput.putchar(route(true).emit(type))
RouteOutput.putchar(route(true).emit(value))
RouteOutput.putchar(10)
