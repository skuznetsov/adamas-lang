@[Link("gc")]

class YieldOwner
  def result(flag : Bool) : Bool
    if flag
      return 65
    end
    yield
    true
  end
end

YieldOwner.new.result(false) { nil }
