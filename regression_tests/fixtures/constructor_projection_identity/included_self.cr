lib LibC
  fun exit(status : Int32) : NoReturn
end

module Action(T)
  def create_context
    Context.new(self)
  end

  def unwait(context : Context)
    7
  end

  def unwait(context : Context(T))
    11
  end
end

class Context(T)
  def initialize(@action : Action(T))
  end
end

class Receiver(T)
  include Action(T)
end

class OtherReceiver(T)
  include Action(T)
end

receiver = Receiver(Int32).new
other = OtherReceiver(Int64).new
context = receiver.create_context
other_context = other.create_context
LibC.exit(1) unless receiver.unwait(context) == 11
LibC.exit(2) unless receiver.unwait(other_context) == 7
LibC.exit(0)
