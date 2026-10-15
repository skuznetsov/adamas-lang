lib C
  fun exit(status : Int32) : NoReturn
end
module Metrics
  alias MetricValue = UInt16 | Int32 | UInt32 | UInt64 | Int64 | Float64
  alias MetricLabels = Hash(String, String) |
                       NamedTuple(name: String) | NamedTuple(vhost: String) |
                       NamedTuple(queue: String, vhost: String)
  alias Metric = NamedTuple(name: String, value: MetricValue) |
                 NamedTuple(name: String, value: MetricValue, labels: MetricLabels) |
                 NamedTuple(name: String, value: MetricValue, help: String) |
                 NamedTuple(name: String, value: MetricValue, type: String, help: String) |
                 NamedTuple(name: String, value: MetricValue, help: String, labels: MetricLabels) |
                 NamedTuple(name: String, value: MetricValue, type: String, help: String, labels: MetricLabels)
  class Reader(T)
    def initialize(@missing : T)
    end
    def has_labels(metric : Metric) : Int32
      if metric[:labels]?
        42
      else
        @missing
      end
    end
  end
end
reader = Metrics::Reader(Int32).new(41)
C.exit(1) unless reader.has_labels({name: "one", value: 42}) == 41
C.exit(2) unless reader.has_labels({name: "two", value: 42, labels: {vhost: "root"}}) == 42
C.exit(3) unless reader.has_labels({name: "three", value: 42_i64, help: "test"}) == 41
C.exit(0)
