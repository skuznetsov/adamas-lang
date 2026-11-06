lib C
  fun putchar(c : Int32) : Int32
end
class MacroIfDefaultBody
  {% if true %}
    def emit(count = 65) : Nil
      C.putchar(count)
    end
  {% end %}
  def trigger : Nil
    emit
    self.emit
  end
end
MacroIfDefaultBody.new.trigger
