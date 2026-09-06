require "set"

lib LibC
  fun exit(status : Int32) : NoReturn
end

value = "module"
members = Set{value, "compiler"}
absolute_members = ::Set{"absolute"}

LibC.exit(1) unless members.size == 2
LibC.exit(2) unless members.includes?(value)
LibC.exit(3) unless absolute_members.includes?("absolute")
LibC.exit(0)
