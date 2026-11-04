@[Link("c")]
lib MacroOutput
  fun putchar(value : Int32) : Int32
end

macro emit_literals
  {%
    a, b = 65, 66
    a, b = b, a
    first, *middle, last = [67, 68, 69, 70]
    *prefix, suffix = {71, 72, 73}
    only, *empty_rest = [74]
    head, *_, end_value = 75, 0, 76
    first_sparse, second_sparse = {77}
    _, tail = {0, 78}
    values = [79, 80]
    values[1], observed = values
    index = 0
    values[index], index = 81, 1
    state = [82, 83]
    nested = [{0, 0}]
    nested[0][-1], nested[0][0] = 85, 84
    _, last_queued = state[0] = state[1], state[0]
    if middle.class_name != "ArrayLiteral" || prefix.class_name != "TupleLiteral" || !empty_rest.empty? || !second_sparse.nil?
      raise "unexpected destructuring result"
    end
  %}
  MacroOutput.putchar({{a}})
  MacroOutput.putchar({{b}})
  MacroOutput.putchar({{first}})
  MacroOutput.putchar({{middle[0]}})
  MacroOutput.putchar({{middle[1]}})
  MacroOutput.putchar({{last}})
  MacroOutput.putchar({{prefix[0]}})
  MacroOutput.putchar({{prefix[-1]}})
  MacroOutput.putchar({{suffix}})
  MacroOutput.putchar({{only}})
  MacroOutput.putchar({{head}})
  MacroOutput.putchar({{end_value}})
  MacroOutput.putchar({{first_sparse}})
  MacroOutput.putchar({{tail}})
  MacroOutput.putchar({{observed}})
  MacroOutput.putchar({{values[0]}})
  MacroOutput.putchar({{last_queued}})
  MacroOutput.putchar({{nested[0][0]}})
  MacroOutput.putchar({{nested[0][1]}})
  MacroOutput.putchar(10)
end

emit_literals
