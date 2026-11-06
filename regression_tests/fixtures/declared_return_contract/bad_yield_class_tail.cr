@[Link("gc")]

class YieldOwner
  def result : Bool
    yield
    65
  end
end

YieldOwner.new.result { nil }
