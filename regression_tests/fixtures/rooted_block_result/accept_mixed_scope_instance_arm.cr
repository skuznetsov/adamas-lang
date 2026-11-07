@[Link("c")]
lib RootedPatternOutput
  fun putchar(value : Int32) : Int32
end

class Path
end

module Scope
  class Path
  end

  alias RootPathClass = ::Path.class

  class Owner
    def self.lexical_class(&block : -> Path.class)
      yield
      RootedPatternOutput.putchar(65)
    end

    def self.rooted_class(&block : -> ::Path.class)
      yield
      RootedPatternOutput.putchar(66)
    end

    def self.mixed(&block : -> Path | ::Path.class)
      yield
      RootedPatternOutput.putchar(67)
    end

    def self.rooted_alias(&block : -> RootPathClass)
      yield
      RootedPatternOutput.putchar(68)
    end
  end
end

Scope::Owner.mixed { Scope::Path.new }
