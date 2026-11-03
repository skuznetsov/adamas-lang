require "./decoy"
require "./declared"
lib LibC
  fun putchar(value : Int32) : Int32
end
LibC.putchar(Wrap::ExactOwner::Options::CODE)
LibC.putchar(10)
