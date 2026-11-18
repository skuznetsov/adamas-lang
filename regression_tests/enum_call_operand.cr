@[Link("c")]
lib Output
  fun putchar(value : Int32) : Int32
end

enum Visibility
  Public = 65
  Protected = 66
end

struct Parser
  def emit(is_abstract : Bool = false, mode : Visibility? = nil) : Int32
    65
  end

  def accept(flag : Bool, mode : Visibility) : Int32
    66
  end

  def probe
    Output.putchar(emit(mode: Visibility::Protected))
    Output.putchar(accept(false, Visibility::Public))
  end
end

Parser.new.probe
Output.putchar(10)
