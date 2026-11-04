lib LibC
  fun exit(status : Int32) : NoReturn
end

class Resource
  def self.open(value : Int64, &)
    open_internal(value) { |resource| yield resource }
    return nil
  end

  protected def self.open_internal(value, &)
    resource = new(value)
    yield resource
  end

  def initialize(@value : Int64)
  end

  def value : Int64
    @value
  end

  def close : Nil
    nil
  end
end

def read(resource : Resource) : Int64
  resource.value
end

Resource.open(2147483649_i64) { |resource| LibC.exit(1) unless read(resource) == 2147483649_i64 }
LibC.exit(0)
