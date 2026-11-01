lib LibC
  fun putchar(value : Int32) : Int32
end

class T
  def rooted_tag : Int32
    82
  end
end

module MacroIncludeRootedLeaf(U)
  def rooted_value : U
    U.new
  end
end

# The leading :: is semantic: the global T must not be rewritten by the
# same-spelling formal captured from Outer(T).
module MacroIncludeRootedOuter(T)
  macro included
    include MacroIncludeRootedLeaf(::T)
  end
end

class MacroIncludeRootedHost
  include MacroIncludeRootedOuter(Int32)
end

LibC.putchar(MacroIncludeRootedHost.new.rooted_value.rooted_tag)
LibC.putchar(10)
