lib Native
  fun putchar(value : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
end

class TerminalOwner
  def self.never : Nil
    Native._exit(0)
  end
end

callback = ->(value : Nil) { Native.putchar(65) }
callback.call(TerminalOwner.never)
Native.putchar(88)
