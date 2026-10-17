class SelectedAnnotationGenericOwner(T)
  def project : Array(T?)
    [@value, nil]
  end

  def initialize(@value : T)
  end

  # Required Bool keeps this distinct from the zero-argument declaration.
  def project(flag : Bool) : Array(T)
    [@value]
  end
end

class SelectedAnnotationMemberOwner(T)
  def project : Array(T?)
    [nil] of T?
  end

  # Required argument avoids optional-arity ambiguity.
  def project(flag : Bool) : Array(T)
    [] of T
  end
end

class SelectedAnnotationGenericParent(T)
  def project : Array(T?)
    [nil] of T?
  end

  def project(flag : Bool) : Array(T)
    [] of T
  end
end

# The parent's T is Array(U), so this checks inherited substitution composition.
class SelectedAnnotationInheritedChild(U) < SelectedAnnotationGenericParent(Array(U))
end

class SelectedAnnotationOptionalOwner(T)
  def optional_project(flag : Bool = true) : Array(T?)
    [nil] of T?
  end
end

# Selected overloads, distinct generic receivers, and reversed call order.
string_owner = SelectedAnnotationGenericOwner(String).new("x")
puts typeof(string_owner.project()) == Array(String?)
puts typeof(string_owner.project(true)) == Array(String)
int_owner = SelectedAnnotationGenericOwner(Int32).new(1)
puts typeof(int_owner.project(true)) == Array(Int32)
puts typeof(int_owner.project()) == Array(Int32?)

# Bare member access and explicit zero-argument CallNode forms.
puts typeof(SelectedAnnotationMemberOwner(String).new.project) == Array(String?)
puts typeof(SelectedAnnotationMemberOwner(Int32).new.project) == Array(Int32?)
puts typeof(SelectedAnnotationMemberOwner(String).new.project()) == Array(String?)
puts typeof(SelectedAnnotationMemberOwner(Int32).new.project()) == Array(Int32?)
puts typeof(SelectedAnnotationMemberOwner(String).new.project(true)) == Array(String)
puts typeof(SelectedAnnotationMemberOwner(Int32).new.project(true)) == Array(Int32)

# Parent generic mapping plus a distinct required-argument sibling.
puts typeof(SelectedAnnotationInheritedChild(String).new.project()) == Array(Array(String)?)
puts typeof(SelectedAnnotationInheritedChild(String).new.project(true)) == Array(Array(String))
puts typeof(SelectedAnnotationInheritedChild(Int32).new.project(true)) == Array(Array(Int32))
puts typeof(SelectedAnnotationInheritedChild(Int32).new.project()) == Array(Array(Int32)?)

# One optional declaration exercises both accepted call arities.
puts typeof(SelectedAnnotationOptionalOwner(String).new.optional_project()) == Array(String?)
puts typeof(SelectedAnnotationOptionalOwner(String).new.optional_project(true)) == Array(String?)
