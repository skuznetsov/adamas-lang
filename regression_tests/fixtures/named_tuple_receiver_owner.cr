lib LibC
  fun exit(status : Int32) : NoReturn
end

struct NamedTuple
  def source_field_count(marker : Int32)
    result = marker
    {% for key, type in T %}
      result = result &+ 1
    {% end %}
    result
  end

  def source_name
    {% for key in T %}
      {% if key.stringify == "name" %}
        return self[{{key.symbolize}}]
      {% end %}
    {% end %}
    0
  end
end

def count_fields(row : NamedTuple, marker : Int32)
  row.source_field_count(marker)
end

def read_name(row : NamedTuple)
  row.source_name
end

def verify(first : Int32, second : Int32, repeat : Int32, name1 : Int32, name2 : Int32)
  return 1 if first != 12
  return 2 if second != 23
  return 3 if repeat != 32
  return 4 if name1 != 11
  return 5 if name2 != 8
  0
end

first = {name: 11, enabled: true}
second = {count: 7, name: 8, other: 9}
LibC.exit(verify(count_fields(first, 10), count_fields(second, 20),
  count_fields(first, 30), read_name(first), read_name(second)))
