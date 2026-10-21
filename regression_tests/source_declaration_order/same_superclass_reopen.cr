lib LibC
  fun putchar(value : Int32) : Int32
end

class ReopenParent
end
class ReopenedChild < ReopenParent
end
class ReopenedChild < ReopenParent
end
LibC.putchar(65_i32)

