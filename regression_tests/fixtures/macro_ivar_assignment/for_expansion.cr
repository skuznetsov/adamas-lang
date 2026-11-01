lib LibC
  fun putchar(value : Int32) : Int32
end
class MacroLock
  def value : Int32
    65
  end
end
class MacroLockOwner
  {% for name in ["lock"] %}
  @{{name.id}} = MacroLock.new
  {% end %}
  def lock : MacroLock
    @lock
  end
end
LibC.putchar(MacroLockOwner.new.lock.value)
LibC.putchar(10)
