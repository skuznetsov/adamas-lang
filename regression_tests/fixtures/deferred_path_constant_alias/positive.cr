lib LibC
  fun putchar(c : Int32) : Int32
end

module DeferredPathConstantAliasProbe
  module Factory
    def self.make : Int32
      LibC.putchar(88)
      65
    end
  end

  module Source
    VALUE = Factory.make

    module Nested
      RELATIVE = VALUE
    end
  end

  module Qualified
    VALUE = DeferredPathConstantAliasProbe::Source::VALUE
  end

  module Absolute
    VALUE = ::DeferredPathConstantAliasProbe::Source::VALUE
  end
end

class DeferredPathConstantAliasStaticOwner
  def self.value : Int32
    66
  end
end

# This is a type path and must not be scheduled as a runtime constant alias.
DEFERRED_PATH_CONSTANT_ALIAS_TYPE_ONLY = DeferredPathConstantAliasStaticOwner

LibC.putchar(DeferredPathConstantAliasProbe::Source::VALUE)
LibC.putchar(DeferredPathConstantAliasProbe::Source::Nested::RELATIVE)
LibC.putchar(DeferredPathConstantAliasProbe::Qualified::VALUE)
LibC.putchar(DeferredPathConstantAliasProbe::Absolute::VALUE)
LibC.putchar(DeferredPathConstantAliasStaticOwner.value)
LibC.putchar(10)
