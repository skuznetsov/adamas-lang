lib LibC
  fun putchar(c : Int32) : Int32
  fun exit(c : Int32) : NoReturn
end
fun __crystal_raise_overflow : NoReturn
  LibC.exit(91)
end
module Registry
  enum Kind : UInt8
    BlockDevice = 65
  end
  @[Flags]
  enum Options : UInt8
    Read = 1
    Write = 2
  end
end
module Shadow
  module Registry
    enum Kind : UInt8
      Other = 88
    end
    enum Options : UInt8
      Other = 88
    end
  end
  class Reader
    def emit
      ::Registry::Kind::Other.value
    end
  end
end
Shadow::Reader.new.emit
