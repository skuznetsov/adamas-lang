lib LibC
  fun putchar(value : Int32) : Int32
end
class MacroOrderParent
  def marker : Int32
    65_i32
  end
end
class MacroOrderDestination
end
{% for child_name in ["GeneratedChild"] %}
  class MacroOrderDestination::{{child_name.id}} < MacroOrderParent
  end
{% end %}
LibC.putchar(MacroOrderDestination::GeneratedChild.new.marker)
