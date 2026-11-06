lib C
  fun putchar(c : Int32) : Int32
end
macro define_default_emitter
  def emit(count = 65) : Nil
    C.putchar(count)
  end
end
class MacroGeneratedDefaultBody
  define_default_emitter
  def trigger : Nil
    emit
    self.emit
  end
end
MacroGeneratedDefaultBody.new.trigger
