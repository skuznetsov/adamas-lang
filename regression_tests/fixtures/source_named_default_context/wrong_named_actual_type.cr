class WrongNamedActualSourceDefaultProbe
  def self.accept(*, value : Int32) : Int32
    value
  end
end

WrongNamedActualSourceDefaultProbe.accept(value: "not-an-int")
