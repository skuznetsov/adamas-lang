lib Output
  fun srand(seed : UInt32) : Void
end
def invalid_void_leaf
  Output.srand("invalid")
end
invalid_void_leaf
