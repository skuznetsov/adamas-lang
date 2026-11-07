lib Output
  fun putchar(c : Int32) : Int32
  fun srand(seed : UInt32) : Void
end

def void_leaf
  Output.srand(1_u32)
end

def void_chain_0
  void_leaf
end

def void_chain_1
  void_chain_0
end

def void_chain_2
  void_chain_1
end

def void_chain_3
  void_chain_2
end

def void_chain_4
  void_chain_3
end

def void_chain_5
  void_chain_4
end

void_chain_5
Output.putchar(65)
Output.putchar(10)
