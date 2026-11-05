lib LibC
  fun putchar(c : Int32) : Int32
end

class VHost
  def initialize(@count : Int32)
  end

  def connections_size : Int32
    @count
  end
end

def write_metric(metric : NamedTuple(value: Int32))
  LibC.putchar(metric[:value])
end

class VHostStore
  include Enumerable({String, VHost})

  def initialize(@vhosts : Hash(String, VHost))
  end

  def each(&)
    @vhosts.each do |kv|
      yield kv
    end
  end
end

class Broker
  def initialize(@vhosts : VHostStore)
  end

  def report
    write_metric({value: @vhosts.sum { |_, v| v.connections_size }})
    write_metric({value: @vhosts.sum(1) { |_, v| v.connections_size }})
  end
end

Broker.new(VHostStore.new({"a" => VHost.new(31), "b" => VHost.new(34)})).report
