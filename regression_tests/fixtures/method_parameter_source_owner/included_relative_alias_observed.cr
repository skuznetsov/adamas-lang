lib LibC
  fun putchar(value : Int32) : Int32
end

module IncludedPayload
  alias Payload = Int32

  def emit(value : Payload)
    LibC.putchar(value)
  end
end

class AliasHost
  include IncludedPayload
end

module CompetingCaller
  alias Payload = String

  def self.run(owner)
    owner.emit(65)
  end
end

CompetingCaller.run(AliasHost.new)
LibC.putchar(10)
