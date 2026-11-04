require "./support/declared_errors"
require "./support/dispatch"

lib LibC
  fun putchar(c : Int32) : Int32
end

LibC.putchar(exception_kind(ArenaRepro::TopError.new))
LibC.putchar(exception_kind(ArenaRepro::Nested::NestedError.new))
