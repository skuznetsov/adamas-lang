module Unrelated
  alias Orphan = Int32
end

class PlainContext
  def self.consume(value : Orphan = 65) : Orphan
    value
  end
end

PlainContext.consume
