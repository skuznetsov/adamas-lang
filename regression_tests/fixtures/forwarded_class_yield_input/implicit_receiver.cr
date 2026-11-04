lib LibC
  fun exit(status : Int32) : NoReturn
end

class Resource
  def self.open(value : Int64, &)
    open_internal(value) { |resource| yield resource }
    # Exercise the standalone callback path.
    return nil
  end

  protected def self.open_internal(value, &)
    resource = new(value)
    yield resource
  end

  def open(&)
    open_internal { |value| yield value }
    return nil
  end

  protected def open_internal(&)
    yield 19_i32
  end

  def initialize(@value : Int64)
  end

  def value : Int64
    @value
  end
end

def read(resource : Resource) : Int64
  resource.value
end

def read_number(value : Int32) : Int32
  value
end

Resource.open(2147483649_i64) do |resource|
  LibC.exit(1) unless read(resource) == 2147483649_i64
end
Resource.new(0_i64).open do |value|
  LibC.exit(2) unless read_number(value) == 19_i32
end
LibC.exit(0)
