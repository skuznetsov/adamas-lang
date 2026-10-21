class Object
end

lib LibC
  fun putchar(value : Int32) : Int32
end

module AMQP
  class Exchange
    def initialize(value : Int32)
      LibC.putchar(71_i32)
    end
  end
end

module Service
  module AMQP
    class Exchange
      def initialize(value : Bool)
        LibC.putchar(65_i32)
      end
    end
  end
  module MQTT
    class Exchange < ::AMQP::Exchange
      def initialize(value : Int32)
        super(value)
      end
    end
  end
end

Service::MQTT::Exchange.new(66_i32)
