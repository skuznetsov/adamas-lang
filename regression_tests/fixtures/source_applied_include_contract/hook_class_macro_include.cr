lib LibC
  fun putchar(value : Int32) : Int32
end

module MacroIncludedHook
  macro included
    def marker : Int32
      66
    end
  end
end

macro include_macro_hook
  include MacroIncludedHook
end

class ClassMacroHookHost
  def marker : Int32
    65
  end

  include_macro_hook()
end

LibC.putchar(ClassMacroHookHost.new.marker)
LibC.putchar(10)
