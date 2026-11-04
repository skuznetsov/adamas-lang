lib MacroSplatOutput
  fun putchar(value : Int32) : Int32
end

def check_splat(a : String, b : Symbol, c : Char, result : Int32)
  MacroSplatOutput.putchar(result)
end

macro expand_splat
  {% tuple = {"-x", :flag, 'C'} %}
  {% array = ["-x", :flag, 'C'] %}
  check_splat({{tuple.splat(", ")}}65)
  check_splat({{array.splat(", ")}}66)
end

expand_splat
MacroSplatOutput.putchar(10)
