lib LibC
  fun putchar(value : Int32) : Int32
end

module MacroIncludeShadowLeaf(T)
  def leaf_value(value : T) : T
    value
  end
end

# The included hook generates a nested generic class in the consumer. Its own
# formal T must bind Leaf(T), even though the hook is declared under Outer(T).
module MacroIncludeShadowOuter(T)
  macro included
    class Inner(T)
      include MacroIncludeShadowLeaf(T)
    end
  end
end

class MacroIncludeShadowHost
  include MacroIncludeShadowOuter(Int32)
end

def macro_include_shadow_tag(value : Int32) : Int32
  65
end

def macro_include_shadow_tag(value : Int64) : Int32
  66
end

# Inner(Int64) must select Leaf(Int64), not the captured Outer(Int32).
LibC.putchar(macro_include_shadow_tag(
  MacroIncludeShadowHost::Inner(Int64).new.leaf_value(66_i64)
))

LibC.putchar(10)
