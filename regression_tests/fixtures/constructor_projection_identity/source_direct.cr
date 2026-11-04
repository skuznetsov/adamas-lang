lib LibC
  fun exit(status : Int32) : NoReturn
end
class Payload
end
module Projection(T)
end
class Context(T)
  def initialize(@projection : Projection(T))
  end
end
module Scoped
  class Payload
  end
  class Local(T)
    include Projection(Payload)
  end
  class Root(T)
    include Projection(::Payload)
  end
end
def nested_identity(x : Context(Scoped::Payload))
  true
end
def root_identity(x : Context(::Payload))
  true
end
LibC.exit(1) unless nested_identity(Context.new(Scoped::Local(Int32).new))
LibC.exit(2) unless root_identity(Context.new(Scoped::Root(Int32).new))
LibC.exit(0)
