lib Output
  fun putchar(value : Int32) : Int32
end

module BareSelfLeft
  class Probe
    def self.value
      65
    end

    def value
      66
    end

    def self.from_class
      value
    end

    def from_instance
      value
    end
  end
end

module BareSelfRight
  class Probe
    def self.value
      67
    end

    def value
      68
    end

    def self.from_class
      value
    end

    def from_instance
      value
    end
  end
end

Output.putchar(BareSelfLeft::Probe.from_class)
Output.putchar(BareSelfLeft::Probe.new.from_instance)
Output.putchar(BareSelfRight::Probe.from_class)
Output.putchar(BareSelfRight::Probe.new.from_instance)
Output.putchar(10)
