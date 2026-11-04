lib LibC
  fun exit(status : Int32) : NoReturn
end

struct NamedTuple
  def source_read(flag : Bool)
    {% if T.size == 2 %}
      flag ? 7 : nil
    {% else %}
      flag ? 4_000_000_000_i64 : false
    {% end %}
  end
end

alias Row = NamedTuple(value: Int32, enabled: Bool) | NamedTuple(count: Int64, value: Int64, other: Int32)

def read_row(row : Row, flag : Bool)
  row.source_read(flag)
end

def choose_row(flag : Bool) : Row
  if flag
    {value: 7, enabled: true}
  else
    {count: 1_i64, value: 4_000_000_000_i64, other: 0}
  end
end

warm = {value: 7, enabled: true}.source_read(true)
LibC.exit(9) unless warm.is_a?(Int32) && warm == 7
a = read_row(choose_row(true), true)
b = read_row(choose_row(false), true)
c = read_row(choose_row(true), false)
d = read_row(choose_row(false), false)
LibC.exit(1) unless a.is_a?(Int32) && a == 7
LibC.exit(2) unless b.is_a?(Int64) && b == 4_000_000_000_i64
LibC.exit(3) unless c.is_a?(Nil)
LibC.exit(4) unless d.is_a?(Bool) && !d
LibC.exit(0)
