lib LibC
 fun putchar(value : Int32) : Int32
end
def marker
 1
end
macro inspect_parts(pattern)
 {% parts = pattern.expressions { 1 } %}
 LibC.putchar(65)
end
inspect_parts "a#{marker}b"
