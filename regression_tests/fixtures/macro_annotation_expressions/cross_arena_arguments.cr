require "./annotation_source"

@[Link("c")]
lib MacroOutput
  fun putchar(value : Int32) : Int32
end

class ReflectedArguments
  def emit
    {% begin %}
      {% reflected = @type.instance_vars[0].annotation(Reflected) %}
      {% unless reflected.args[0].is_a?(ProcPointer) %}
        {% raise "expected a ProcPointer AST node" %}
      {% end %}
      {% unless reflected.args[0].stringify == "->::ReflectionSource::Transform.value(Int32)" %}
        {% raise "reflection dropped the rooted path" %}
      {% end %}
      callback = {{reflected.args[0]}}
      MacroOutput.putchar(callback.call(65))
      MacroOutput.putchar({{reflected[:named]}})
      MacroOutput.putchar({{reflected.args[1].is_a?(NilLiteral) ? 67 : 88}})
      MacroOutput.putchar({{reflected.args[2] == 'x' ? 68 : 88}})
      MacroOutput.putchar(10)
    {% end %}
  end
end

ReflectedArguments.new.emit
