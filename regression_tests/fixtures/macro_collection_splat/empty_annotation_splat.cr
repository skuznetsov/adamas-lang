lib MacroSplatOutput
  fun putchar(value : Int32) : Int32
end

annotation CliOption
end

class ConfigProbe
  @[CliOption]
  @extra : Int32 = 0

  def emit
    {% for ivar in @type.instance_vars.select(&.annotation(CliOption)) %}
      {% opt = ivar.annotation(CliOption) %}
      MacroSplatOutput.putchar({{opt.args.splat(", ")}}65)
    {% end %}
    MacroSplatOutput.putchar(10)
  end
end

ConfigProbe.new.emit
