class Object
end

lib LibC
  fun putchar(value : Int32) : Int32
end

module AMQP
  class Exchange
    def initialize(value : Int32)
      LibC.putchar(70_i32)
    end
  end
end

module Other
  module MQTT
    class Exchange < AMQP::Exchange
      def initialize(value : Int32)
        super(value)
      end
    end
  end
end

Other::MQTT::Exchange.new(67_i32)
