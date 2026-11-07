@[Link("c")]
lib LibC
  fun putchar(c : Int32) : Int32
end
macro begin_value
  {% unused = begin
    raise "begin first error marker"
    [1].all?
  end %}
  65
end
LibC.putchar(begin_value)
