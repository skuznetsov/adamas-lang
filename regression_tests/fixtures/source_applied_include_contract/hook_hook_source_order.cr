lib LibC
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
fun __crystal_raise_overflow : NoReturn
  LibC.exit(251)
end
module FirstHookSource
  macro included
    def hook_marker : Int32
      65
    end
  end
end
module LastHookSource
  macro included
    def hook_marker : Int32
      66
    end
  end
end
class HookHostAB
  include FirstHookSource
  include LastHookSource
end
class HookHostBA
  include LastHookSource
  include FirstHookSource
end
LibC.putchar(HookHostAB.new.hook_marker)
LibC.putchar(HookHostBA.new.hook_marker)
LibC.putchar(10)
