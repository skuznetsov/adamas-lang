@[Link("c")]
lib MacroOutput
  fun putchar(value : Int32) : Int32
end

annotation MacroValue
end

module Transform
  def self.upper(value : Int32) : Int32
    value &- 32
  end
end

class Annotated
  @[MacroValue(->::Transform.upper(Int32), nested: Transform.upper(98))]
  @first : Int32 = 0

  @[MacroValue(->local(Int32), nested: Transform.upper(100))]
  @second : Int32 = 0

  def local(value : Int32) : Int32
    value &- 32
  end

  def emit
    {% for ivar, loop_index in @type.instance_vars.select(&.annotation(MacroValue)) %}
      {% reflected = ivar.annotation(MacroValue) %}
      callback = {{reflected.args[0]}}
      MacroOutput.putchar(callback.call({{97 + loop_index * 2}}))
      MacroOutput.putchar({{reflected[:nested]}})
    {% end %}
    MacroOutput.putchar(10)
  end
end

Annotated.new.emit
