lib LibC
  fun putchar(value : Int32) : Int32
end
require "./dependencies/parent"
{% for child_name in ["GeneratedChild"] %}
  class {{child_name.id}} < MacroOrderParent
  end
{% end %}
LibC.putchar(GeneratedChild.new.marker)
