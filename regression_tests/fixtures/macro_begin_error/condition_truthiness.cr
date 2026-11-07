lib LibC
  fun putchar(value : Int32) : Int32
end

macro condition_0
  {% if begin 0 end %}
    65
  {% else %}
    66
  {% end %}
end
LibC.putchar(condition_0)

macro condition_1
  {% if begin "" end %}
    65
  {% else %}
    66
  {% end %}
end
LibC.putchar(condition_1)

macro condition_2
  {% if begin false end %}
    65
  {% else %}
    66
  {% end %}
end
LibC.putchar(condition_2)

macro condition_3
  {% if begin nil end %}
    65
  {% else %}
    66
  {% end %}
end
LibC.putchar(condition_3)

macro condition_4
  {% if begin  end %}
    65
  {% else %}
    66
  {% end %}
end
LibC.putchar(condition_4)
LibC.putchar(10)
