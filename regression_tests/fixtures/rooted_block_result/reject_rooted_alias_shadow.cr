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
  alias RootPathClassAgain = RootPathClass
  alias LexicalPathClass = Path.class

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

    def self.lexical_alias(&block : -> LexicalPathClass)
      yield
      RootedPatternOutput.putchar(70)
    end

    def self.rooted_alias_again(&block : -> RootPathClassAgain)
      yield
      RootedPatternOutput.putchar(71)
    end

    def self.rooted_alias(&block : -> RootPathClass)
      yield
      RootedPatternOutput.putchar(68)
    end
  end
end

Scope::Owner.rooted_alias { Scope::Path }
