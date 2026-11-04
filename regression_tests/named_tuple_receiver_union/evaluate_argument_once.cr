lib LibC
  fun exit(status : Int32) : NoReturn
end

struct NamedTuple
  def lookup(index : Int32)
    {% for name, field_type, position in T %}
      return self[{{ name.symbolize }}] if index == {{ position }}
    {% end %}
    nil
  end
end

def row(flag : Bool)
  flag ? {value: 17, active: false} : {state: true, value: 42_i64}
end

def check(row : NamedTuple, index : Int32)
  evaluated = false
  value = row.lookup(begin
    LibC.exit(10) if evaluated
    evaluated = true
    index
  end)
  LibC.exit(11) unless evaluated
  value
end

first = row(true)
second = row(false)
a = check(first, 0)
b = check(second, 1)
c = check(first, 1)
d = check(second, 0)
LibC.exit(1) unless a.is_a?(Int32) && a == 17
LibC.exit(2) unless b.is_a?(Int64) && b == 42_i64
LibC.exit(3) unless c.is_a?(Bool) && !c
LibC.exit(4) unless d.is_a?(Bool) && d
LibC.exit(5) unless check(first, 2).is_a?(Nil)
LibC.exit(6) unless check(second, 2).is_a?(Nil)
LibC.exit(0)
