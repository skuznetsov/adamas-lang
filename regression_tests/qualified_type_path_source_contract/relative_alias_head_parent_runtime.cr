class Object
end

lib SuperContractLibC
  fun putchar(value : Int32) : Int32
end

module ParentHead
  class Exchange
    def initialize(value : Bool)
      SuperContractLibC.putchar(71_i32)
    end
  end
end

module Service
  module AMQP
    class Exchange
      def initialize(value : Bool)
        SuperContractLibC.putchar(65_i32)
      end
    end
  end
  alias ParentHead = AMQP
  module MQTT
    class Exchange < ParentHead::Exchange
      def initialize(value : Bool)
        super(value)
      end
    end
  end
end

Service::MQTT::Exchange.new(true)
