class SelectedDefaultOverload
  @@default_calls = 0

  getter marker : Int32

  def self.for_integer : Int32
    @@default_calls += 1
    11
  end

  def self.for_string : Int32
    @@default_calls += 1
    22
  end

  def self.default_calls : Int32
    @@default_calls
  end

  def initialize(value : Int32, marker : Int32 = SelectedDefaultOverload.for_integer)
    @marker = marker
  end

  def initialize(value : String, marker : Int32 = SelectedDefaultOverload.for_string)
    @marker = marker
  end
end

integer_default = SelectedDefaultOverload.new(1)
string_default = SelectedDefaultOverload.new("x")
integer_explicit = SelectedDefaultOverload.new(1, 33)
puts integer_default.marker
puts string_default.marker
puts integer_explicit.marker
puts SelectedDefaultOverload.default_calls
