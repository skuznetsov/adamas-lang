require "object/properties"

NAMES = {:root_count}

module QualifiedCounters
  NAMES = {:global_qualified_count}
end

module CounterScope
  NAMES = {:outer_count}

  module Counters
    NAMES = [:module_count]

    {% for name in NAMES %}
      def {{ name.id }} : Int64
        44_i64
      end
    {% end %}
  end

  class EarlyQualified
    {% for name in QualifiedCounters::NAMES %}
      getter {{ name.id }} = 77_i64
    {% end %}
  end

  module QualifiedCounters
    NAMES = {:nested_qualified_count}
  end

  class Server
    include Counters
    NAMES = {:user_count, :system_count}

    {% for name, index in NAMES %}
      getter {{ name.id }} = {{ 11_i64 + index }}
    {% end %}

    {% for name in QualifiedCounters::NAMES %}
      getter {{ name.id }} = 88_i64
    {% end %}

    {% for name in ::NAMES %}
      getter {{ name.id }} = 33_i64
    {% end %}
  end

  class Sibling
    {% for name in NAMES %}
      getter {{ name.id }} = 55_i64
    {% end %}
  end
end

module IncludedCounters
  NAMES = {:included_count}
end

class BeforeInclude
  {% for name in NAMES %}
    getter {{ name.id }} = 99_i64
  {% end %}

  include IncludedCounters
end

class AfterInclude
  include IncludedCounters

  {% for name in NAMES %}
    getter {{ name.id }} = 100_i64
  {% end %}
end

class BeforeLocal
  {% for name in NAMES %}
    getter {{ name.id }} = 66_i64
  {% end %}

  NAMES = {:late_count}
end

lib CounterProbeC
  fun putchar(value : Int32) : Int32
end

server = CounterScope::Server.new
CounterProbeC.putchar(server.user_count == 11_i64 ? 65 : 88)
CounterProbeC.putchar(server.system_count == 12_i64 ? 66 : 88)
CounterProbeC.putchar(server.root_count == 33_i64 ? 67 : 88)
CounterProbeC.putchar(server.module_count == 44_i64 ? 68 : 88)
CounterProbeC.putchar(CounterScope::Sibling.new.outer_count == 55_i64 ? 69 : 88)
CounterProbeC.putchar(BeforeLocal.new.root_count == 66_i64 ? 70 : 88)
CounterProbeC.putchar(CounterScope::EarlyQualified.new.global_qualified_count == 77_i64 ? 71 : 88)
CounterProbeC.putchar(server.nested_qualified_count == 88_i64 ? 72 : 88)
CounterProbeC.putchar(BeforeInclude.new.root_count == 99_i64 ? 73 : 88)
CounterProbeC.putchar(AfterInclude.new.included_count == 100_i64 ? 74 : 88)
CounterProbeC.putchar(10)
