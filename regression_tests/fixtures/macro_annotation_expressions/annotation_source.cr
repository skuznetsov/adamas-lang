annotation Reflected
end

module ReflectionSource
  module Transform
    def self.value(value : Int32) : Int32
      value
    end
  end
end

class ReflectedArguments
  @[Reflected(->::ReflectionSource::Transform.value(Int32), nil, 'x', named: ReflectionSource::Transform.value(66))]
  @value : Int32 = 0
end
