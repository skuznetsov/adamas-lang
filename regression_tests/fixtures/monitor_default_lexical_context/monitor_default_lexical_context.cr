lib LibC
  fun putchar(c : Int32) : Int32
end

class DirectToken
  def byte : Int32
    65
  end
end

class AliasToken
  def byte : Int32
    67
  end
end

class ParentToken
  def byte : Int32
    68
  end
end

class IncludedToken
  def byte : Int32
    69
  end
end

class WrongToken
  def byte : Int32
    66
  end
end

class DirectFactory
end

class DirectOwner
  DEFAULT = DirectFactory.default

  def initialize(@token = DEFAULT)
  end

  def byte : Int32
    @token.byte
  end
end

class DirectFactory
  def self.default : DirectToken
    DirectToken.new
  end
end

class AliasFactory
end

class AliasOwner
  DEFAULT = AliasFactory.default
  DEFAULT_ALIAS = DEFAULT

  def initialize(@token = DEFAULT_ALIAS)
  end

  def byte : Int32
    @token.byte
  end
end

class AliasFactory
  def self.default : AliasToken
    AliasToken.new
  end
end

class ParentFactory
end

class ParentOwner
  DEFAULT = ParentFactory.default

  def initialize(@token = DEFAULT)
  end

  def byte : Int32
    @token.byte
  end
end

class ChildOwner < ParentOwner
  DEFAULT = WrongToken.new
end

class ParentFactory
  def self.default : ParentToken
    ParentToken.new
  end
end

class IncludedFactory
end

module IncludedDefaultOwner
  DEFAULT = IncludedFactory.default

  def initialize(@token = DEFAULT)
  end

  def byte : Int32
    @token.byte
  end
end

class IncludedReceiver
  DEFAULT = WrongToken.new
  include IncludedDefaultOwner
end

class IncludedFactory
  def self.default : IncludedToken
    IncludedToken.new
  end
end

module CallerScope
  DEFAULT = WrongToken.new
  DEFAULT_ALIAS = WrongToken.new

  def self.emit
    LibC.putchar(DirectOwner.new.byte)
    LibC.putchar(AliasOwner.new.byte)
    LibC.putchar(ChildOwner.new.byte)
    LibC.putchar(IncludedReceiver.new.byte)
    LibC.putchar(10)
  end
end

CallerScope.emit
