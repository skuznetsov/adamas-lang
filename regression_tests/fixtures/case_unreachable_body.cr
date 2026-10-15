lib LibC
  fun exit(status : Int32) : NoReturn
end

class NeverEach
  def each(&)
    {% raise "unreachable case body was instantiated" %}
  end
end

def classify(flag : Bool)
  value = flag ? nil : true
  case value
  when NeverEach
    value.each { |item| item }
  when Bool
    41
  else
    42
  end
end

LibC.exit(1) unless classify(false) == 41
LibC.exit(2) unless classify(true) == 42
LibC.exit(0)
