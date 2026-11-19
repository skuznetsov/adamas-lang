lib C
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

module Scope
  class NoReturn
  end

  def self.stop : ::NoReturn
    C.putchar(83)
    C.exit(0)
  end

  def self.checked_result(value : Nil) : Int32
    value || stop
  end
end

Scope.checked_result(nil)
