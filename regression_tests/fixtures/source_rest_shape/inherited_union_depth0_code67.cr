struct Int32
  @[Primitive(:binary)]
  def ==(other : Int32) : Bool
  end
  def ===(other : Int32) : Bool
    self == other
  end
end
lib Native
  fun putchar(value : Int32) : Int32
end
class Object
  def tap(&)
    yield self
    self
  end
end
module ErrorSource
  module ClassMethods
    def create(message : Int32?, code : Int32, **opts)
      message = self.build_message(message, **opts)
      self.new_from_code(message, code, **opts).tap { |e| e.code = code }
    end
    def build_message(message : Int32?, **opts) : Int32?
      message
    end
    def new_from_code(message : Int32?, code, **opts)
      self.new(message, **opts)
    end
  end
end
class IOError
  extend ErrorSource::ClassMethods
  def initialize(@message : Int32? = nil, *, target = nil)
    @code = 65
  end
  def code : Int32
    @code
  end
  def code=(@code : Int32)
  end
end
class SocketError < IOError
  private def self.new_from_code(message, code, **opts)
    case code
    when 65
      ConnectError.new(message, **opts)
    when 66
      BindError.new(message, **opts)
    else
      super message, code, **opts
    end
  end
end
class ConnectError < SocketError
end
class BindError < SocketError
end
class Entry0
  def self.call(message, code)
    BindError.create(message, code)
  end
end
class Entry1
  def self.call(message, code)
    Entry0.call(message, code)
  end
end
class Entry2
  def self.call(message, code)
    Entry1.call(message, code)
  end
end
class Entry3
  def self.call(message, code)
    Entry2.call(message, code)
  end
end
class Entry4
  def self.call(message, code)
    Entry3.call(message, code)
  end
end
class Entry5
  def self.call(message, code)
    Entry4.call(message, code)
  end
end
Native.putchar(Entry0.call(65, 67).code)
Native.putchar(10)
