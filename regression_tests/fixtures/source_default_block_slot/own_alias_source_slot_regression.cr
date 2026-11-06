@[Link("c")]
lib SourceBlockAliasOutput
  fun putchar(value : Int32) : Int32
end

class SourceBlockAliasFactory(K, V)
  def self.new(initial_capacity = nil, &block : -> V)
    yield
  end

  def self.with_key(key : K, initial_capacity = nil, &block : K -> V)
    yield key
  end
end

module AliasScope
  class BaseUser
    alias Permissions = NamedTuple(config: Int32, read: Int32, write: Int32)
  end

  class User < BaseUser
    alias OwnPermissions = NamedTuple(config: Int32, read: Int32, write: Int32)
    alias Again = OwnPermissions
    alias MaybePermissions = OwnPermissions | Nil
  end
end
value = SourceBlockAliasFactory(String, AliasScope::User::OwnPermissions).new { {config: 65, read: 66, write: 67} }
SourceBlockAliasOutput.putchar(value[:config])
