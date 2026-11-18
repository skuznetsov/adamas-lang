require "./routes"

RouteOutput.putchar(route(true).emit(KindToken))
RouteOutput.putchar(route(true).emit(KindToken.new))
RouteOutput.putchar(route(false).emit(KindToken.new))
RouteOutput.putchar(route(false).emit(KindToken))
RouteOutput.putchar(10)
