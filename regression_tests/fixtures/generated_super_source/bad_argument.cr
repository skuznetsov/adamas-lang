module StrictSuperBase
  def value(x : Int32) : Int32
    x
  end
end
class StrictSuperProbe
  include StrictSuperBase
  def value(x : Int32)
    super
  end
end
StrictSuperProbe.new.value("bad")
