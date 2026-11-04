module Endpoint
end

module Platform
  module Endpoint
    class Error
      def self.make
        7
      end
    end
  end

  def self.call
    ::Endpoint::Error.make()
  end
end

Platform.call
