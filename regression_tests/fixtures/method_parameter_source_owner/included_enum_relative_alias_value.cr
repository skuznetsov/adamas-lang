lib LibC
  fun putchar(value : Int32) : Int32
end

abstract struct Enum
  def value : Int
    previous_def
  end
end

module IncludedEnumScope
  enum Payload
    Marker = 65
  end
end

module EnumOverloadProbe
  def self.classify(value : IncludedEnumScope::Payload)
    if value.value == 65
      65
    else
      88
    end
  end

  def self.classify(value : Int32)
    if value == 65
      66
    else
      88
    end
  end
end

module IncludedEnumScope
  alias Value = Payload

  def route(value : Value)
    EnumOverloadProbe.classify(value)
  end
end

class EnumAliasHost
  include IncludedEnumScope
end

module CompetingEnumCaller
  alias Value = Int32

  def self.route(host)
    host.route(IncludedEnumScope::Payload::Marker)
  end
end

LibC.putchar(CompetingEnumCaller.route(EnumAliasHost.new))
LibC.putchar(10)
