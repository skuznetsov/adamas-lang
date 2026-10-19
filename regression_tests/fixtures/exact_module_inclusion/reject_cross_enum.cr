lib QualifiedC
  fun putchar(value : Int32) : Int32
end

class StrictDeclarationOwner; end
enum StrictDeclarationOwner::State
  Ready
end
enum StrictDeclarationOwner::Other
  Ready
end

def only_state(value : StrictDeclarationOwner::State)
  QualifiedC.putchar(65)
end
only_state(StrictDeclarationOwner::Other::Ready)
