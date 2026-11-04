lib MacroSplatOutput
  fun putchar(value : Int32) : Int32
end

annotation CliOption
end

class OptionProbe
  def initialize(short : String, long : String, description : String)
    MacroSplatOutput.putchar(65)
  end
end

class ConfigProbe
  @[CliOption("-x", "--extra", "extra options")]
  @extra : Int32 = 0

  def emit
    {% for ivar in @type.instance_vars.select(&.annotation(CliOption)) %}
      {% opt = ivar.annotation(CliOption) %}
      OptionProbe.new({{opt.args.splat}})
    {% end %}
    MacroSplatOutput.putchar(10)
  end
end

ConfigProbe.new.emit
