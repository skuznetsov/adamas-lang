lib Output
  fun putchar(c : Int32) : Int32
end
def discard_leaf : Void
  Output.putchar(65)
  123
end
def discard_caller
  discard_leaf
end
discard_caller
Output.putchar(10)
