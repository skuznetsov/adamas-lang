@[Link("c")]
lib MacroArgOutput
  fun putchar(value : Int32) : Int32
end

annotation MacroArg
end

def emit_macro_args(a : Int32, b : Int32, c : Int32)
  MacroArgOutput.putchar(a)
  MacroArgOutput.putchar(b)
  MacroArgOutput.putchar(c)
end

class MacroArgOwner
  @[MacroArg(65, 66, 67)]
  @direct : Int32 = 0

  @[MacroArg(68, 69, 70, Int32)]
  @destructured : Int32 = 0

  def emit
    {% begin %}
      {% for ivar in @type.instance_vars.select(&.annotation(MacroArg)) %}
        {%
          opt = ivar.annotation(MacroArg)
          if opt.args.size == 3
            args = opt.args
            type = ivar.type
          else
            *args, type = opt.args
          end
        %}
        emit_macro_args({{args.splat}})
      {% end %}
    {% end %}
    MacroArgOutput.putchar(10)
  end
end

MacroArgOwner.new.emit
