require "object/properties"

class TransientGetterPrimaryProbe
  {% for name in {:alpha, :bravo} %}
    getter {{name.id}} = 1
  {% end %}
end

class TransientGetterSiblingProbe
  {% for name in {:gamma, :delta} %}
    getter {{name.id}} = 2
  {% end %}
end

lib TransientGetterProbeC
  fun putchar(value : Int32) : Int32
end

primary = TransientGetterPrimaryProbe.new
sibling = TransientGetterSiblingProbe.new
TransientGetterProbeC.putchar(primary.alpha | 48)
TransientGetterProbeC.putchar(primary.bravo | 48)
TransientGetterProbeC.putchar(sibling.gamma | 48)
TransientGetterProbeC.putchar(sibling.delta | 48)
TransientGetterProbeC.putchar(10)
