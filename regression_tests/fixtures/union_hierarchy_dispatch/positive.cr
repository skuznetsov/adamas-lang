lib UnionHierarchyNative
  fun putchar(value : Int32) : Int32
end

abstract class DispatchRoot
  abstract def code : Int32
  abstract def code(value : Int32) : Int32
end

# Reverse declaration order relative to the calls and the union spelling.
class DispatchRight < DispatchRoot
  def code : Int32
    66
  end

  def code(value : Int32) : Int32
    69
  end
end

class DispatchLeft < DispatchRoot
  def code : Int32
    65
  end

  def code(value : Int32) : Int32
    68
  end
end

class DispatchOther
  def code : Int32
    67
  end

  def code(value : Int32) : Int32
    70
  end
end

class DispatchParent
  def code : Int32
    68
  end
end

class DispatchChild < DispatchParent
  def code : Int32
    69
  end
end

class DispatchGrandchild < DispatchChild
  def code : Int32
    70
  end
end

class DispatchInherited < DispatchParent
end

def bare(value : DispatchRoot | DispatchOther)
  UnionHierarchyNative.putchar(value.code)
end

def parenthesized(value : DispatchOther | DispatchRoot)
  UnionHierarchyNative.putchar(value.code())
end

def with_argument(value : DispatchRoot | DispatchOther)
  UnionHierarchyNative.putchar(value.code(1))
end

def concrete(value : DispatchParent | DispatchOther)
  UnionHierarchyNative.putchar(value.code)
end

# Return contracts retain the union at each consumer callsite even when the
# selected runtime object is a concrete descendant.
def root_value(left : Bool, right : Bool) : DispatchRoot | DispatchOther
  if left
    DispatchLeft.new
  elsif right
    DispatchRight.new
  else
    DispatchOther.new
  end
end

def parent_value(child : Bool, grandchild : Bool, inherited : Bool, other : Bool) : DispatchParent | DispatchOther
  if child
    DispatchChild.new
  elsif grandchild
    DispatchGrandchild.new
  elsif inherited
    DispatchInherited.new
  elsif other
    DispatchOther.new
  else
    DispatchParent.new
  end
end

bare(root_value(true, false))
bare(root_value(false, true))
bare(root_value(false, false))
parenthesized(root_value(false, false))
parenthesized(root_value(false, true))
parenthesized(root_value(true, false))
with_argument(root_value(true, false))
with_argument(root_value(false, true))
with_argument(root_value(false, false))
concrete(parent_value(false, false, false, false))
concrete(parent_value(true, false, false, false))
concrete(parent_value(false, true, false, false))
concrete(parent_value(false, false, true, false))
concrete(parent_value(false, false, false, true))
UnionHierarchyNative.putchar(10)
