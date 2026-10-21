lib LibC
  fun putchar(value : Int32) : Int32
end

class RequireOwner
end
class RequireChild < RequireOwner::Missing
end
