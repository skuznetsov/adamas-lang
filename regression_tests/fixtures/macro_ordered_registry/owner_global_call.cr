lib LibC
 fun putchar(value : Int32) : Int32
end
class Object
 macro owner_choice
  LibC.putchar(66)
 end
end
macro owner_choice
 LibC.putchar(65)
end
owner_choice
