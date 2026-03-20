abstract class Base
end

class Child < Base
end

raw : Object = Child.new
puts(raw.as?(Child) ? 1 : 0)

base = raw.as(Base)
puts(base.is_a?(Child) ? 1 : 0)
