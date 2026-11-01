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
  def marker : Int32; 65; end
  include HookSource
end
LibC.putchar(HookHost.new.marker)
LibC.putchar(10)
