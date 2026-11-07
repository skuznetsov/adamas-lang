@[Link("c")]
lib LibC
  fun putchar(c : Int32) : Int32
end
{% unused = begin
  raise "begin first error marker"
  [1].all?
end %}
LibC.putchar(65)
