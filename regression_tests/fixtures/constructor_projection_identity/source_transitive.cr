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
  module LocalProjection(T)
    include Projection(Payload)
  end
  module RootProjection(T)
    include Projection(::Payload)
  end
end
class Projected(T)
  include Scoped::LocalProjection(T)
end
class Rooted(T)
  include Scoped::RootProjection(T)
end
def nested_identity(x : Context(Scoped::Payload))
  true
end
def root_identity(x : Context(::Payload))
  true
end
nested = Context.new(Projected(Int32).new)
rooted = Context.new(Rooted(Int32).new)
LibC.exit(1) unless nested_identity(nested)
LibC.exit(2) unless root_identity(rooted)
LibC.exit(0)
