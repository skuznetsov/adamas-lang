lib Native
 fun putchar(value : Int32) : Int32
end
class NamedParent
 def initialize(value : Int32, *, file : Int32)
  Native.putchar(value)
  Native.putchar(file)
 end
 def initialize(value : Int32, *, path : Int32)
  Native.putchar(path)
  Native.putchar(value)
 end
end
class NamedChild < NamedParent
end
NamedChild.new(65, file: 66)
NamedChild.new(67, path: 68)
Native.putchar(10)
