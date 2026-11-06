@[Link("c")]
lib DefaultNoReturnC
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

class TerminalDefault
  def initialize(value : Int32 = terminate)
    DefaultNoReturnC.putchar(66)
  end

  private def terminate : NoReturn
    DefaultNoReturnC.putchar(65)
    DefaultNoReturnC.exit(0)
  end
end

TerminalDefault.new
DefaultNoReturnC.putchar(67)
