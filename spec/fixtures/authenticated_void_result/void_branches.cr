lib Output
  fun putchar(c : Int32) : Int32
  fun srand(seed : UInt32) : Void
end
def void_branch(flag : Bool)
  if flag
    Output.srand(1_u32)
  else
    Output.srand(2_u32)
  end
end
def void_branch_caller
  void_branch(true)
end
void_branch_caller
Output.putchar(65)
Output.putchar(10)
