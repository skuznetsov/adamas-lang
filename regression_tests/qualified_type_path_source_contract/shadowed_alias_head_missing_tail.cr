class Object
end

module ParentHead
  class Exchange
  end
end

module Service
  module AMQP
  end
  alias ParentHead = AMQP
  module MQTT
    class Exchange < ParentHead::Exchange
    end
  end
end

Service::MQTT::Exchange.new
