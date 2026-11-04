lib LibC
  fun exit(status : Int32) : NoReturn
end

class ParentError
end

class Endpoint
  class Error < ParentError
    def self.make
      new
    end
  end
end

alias EndpointAlias = Endpoint
alias EndpointError = Endpoint::Error

module Platform
  module Endpoint
    class Error
      def self.make
        new
      end
    end

    alias EndpointAlias = Endpoint
    alias EndpointError = Error

    def self.with_block
      yield
    end

    def self.accept_root(value : ParentError)
      5
    end

    def self.accept_nested(value : ::Platform::Endpoint::Error)
      7
    end

    def self.rooted
      accept_root(::Endpoint::Error.make)
    end

    def self.rooted_in_block
      with_block { accept_root(::Endpoint::Error.make()) }
    end

    def self.relative
      accept_nested(Endpoint::Error.make())
    end

    def self.rooted_aliases
      accept_root(::EndpointAlias::Error.make) == 5 && accept_root(::EndpointError.make()) == 5
    end
  end
end

LibC.exit(12) unless Platform::Endpoint.rooted == 5
LibC.exit(13) unless Platform::Endpoint.rooted_in_block == 5
LibC.exit(14) unless Platform::Endpoint.relative == 7
LibC.exit(15) unless Platform::Endpoint.rooted_aliases
LibC.exit(0)
