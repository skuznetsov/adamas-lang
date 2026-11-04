lib LibC
  fun exit(status : Int32) : NoReturn
end

struct KeyLoop(T)
  def single
    result = 0
    {% for key in T %}
      {% if key.stringify == "name" %}
        result = result &+ 1
      {% elsif key.stringify == "enabled" %}
        result = result &+ 2
      {% else %}
        result = result &+ 16
      {% end %}
    {% end %}
    result
  end

  def pair
    result = 0
    {% for key, type in T %}
      {% if key.stringify == "name" && type.stringify == "Int32" %}
        result = result &+ 1
      {% elsif key.stringify == "enabled" && type.stringify == "Bool" %}
        result = result &+ 2
      {% else %}
        result = result &+ 16
      {% end %}
    {% end %}
    result
  end

  def indexed
    result = 0
    {% for key, type, index in T %}
      {% if key.stringify == "name" && type.stringify == "Int32" && index == 0 %}
        result = result &+ 1
      {% elsif key.stringify == "enabled" && type.stringify == "Bool" && index == 1 %}
        result = result &+ 2
      {% else %}
        result = result &+ 16
      {% end %}
    {% end %}
    result
  end
end

struct SequenceLoop(T)
  def indexed
    result = 0
    {% for type, index in T %}
      {% if type.stringify == "Int32" && index == 0 %}
        result = result &+ 1
      {% elsif type.stringify == "Bool" && index == 1 %}
        result = result &+ 2
      {% else %}
        result = result &+ 16
      {% end %}
    {% end %}
    result
  end
end

def verify(pair : Int32, single : Int32, mapping_index : Int32, sequence_index : Int32) : Int32
  if pair != 3
    return 1
  end
  if single != 3
    return 2
  end
  if mapping_index != 3
    return 3
  end
  if sequence_index != 3
    return 4
  end
  0
end

mapping = KeyLoop(NamedTuple(name: Int32, enabled: Bool)).new
sequence = SequenceLoop(Tuple(Int32, Bool)).new
LibC.exit(verify(mapping.pair, mapping.single, mapping.indexed, sequence.indexed))
