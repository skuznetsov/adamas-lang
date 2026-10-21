class Object
end

module AMQP
  class Exchange
  end
end

module Service
  module AMQP
  end
  module MQTT
    class Exchange < AMQP::Exchange
    end
  end
end

Service::MQTT::Exchange.new
