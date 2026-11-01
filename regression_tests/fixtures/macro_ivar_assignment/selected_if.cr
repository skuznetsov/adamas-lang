lib LibC
  fun putchar(value : Int32) : Int32
end
class MacroLock
  def value : Int32
    65
  end
end
class MacroLockOwner
  {% if true %}
  @lock = MacroLock.new
  {% else %}
  @unused = false
  {% end %}
  def lock : MacroLock
    @lock
  end
end
LibC.putchar(MacroLockOwner.new.lock.value)
LibC.putchar(10)
