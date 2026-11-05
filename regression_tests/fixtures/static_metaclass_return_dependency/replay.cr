lib LibC
  fun putchar(c : Int32) : Int32
end

class Marker
  def self.code : Int32
    65
  end
end

class Other
  def self.code : Int32
    67
  end
end

struct Reflect(T)
  def self.type
    {% if T.union? %}
      {{ raise("Expected one type") }}
    {% else %}
      T
    {% end %}
  end
end

def once(&)
  yield
end

class Reporter
  def code(reflect)
    type = reflect.type
    if type.responds_to?(:code)
      type.code
    else
      66
    end
  end

  def report
    once { LibC.putchar(code(Reflect(Marker))) }
    once { LibC.putchar(code(Reflect(Other))) }
    once { LibC.putchar(code(Reflect(Marker))) }
  end
end

Reporter.new.report
