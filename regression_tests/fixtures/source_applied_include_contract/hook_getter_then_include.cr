require "object/properties"
lib LibC
  fun putchar(value : Int32) : Int32
end
module HookSource
  macro included
    def marker : Int32
      66
    end
  end
end
class HookHost
  getter marker : Int32 = 65
  include HookSource
end
LibC.putchar(HookHost.new.marker)
LibC.putchar(10)
