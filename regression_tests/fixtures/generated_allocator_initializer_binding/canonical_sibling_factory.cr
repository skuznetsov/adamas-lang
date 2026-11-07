lib OracleC
  fun putchar(value : Int32) : Int32
end
module ErrorFactory
  def from_error(message : String?, error)
    self.new(message)
  end
end
class BaseError
  extend ErrorFactory
  def initialize(message : String? = nil)
    OracleC.putchar(65)
  end
end
class LeftError < BaseError
end
class RightError < BaseError
end
LeftError.from_error("x", 0)
RightError.from_error("y", 0)
OracleC.putchar(10)
