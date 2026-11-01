lib LibC
  fun putchar(c : Int32) : Int32
end

module SchedulerBranchProbe
  class ModernScheduler
    def byte : Int32
      65
    end
  end

  class LegacyScheduler
    def byte : Int32
      66
    end
  end

  {% if !flag?(:without_mt) && !flag?(:preview_mt) || flag?(:execution_context) %}
    class Current
      def self.current : ModernScheduler
        ModernScheduler.new
      end
    end
  {% else %}
    class Current
      def self.current : LegacyScheduler
        LegacyScheduler.new
      end
    end
  {% end %}
end

def main : Int32
  LibC.putchar(SchedulerBranchProbe::Current.current.byte)
  LibC.putchar(10)
  0
end

main
