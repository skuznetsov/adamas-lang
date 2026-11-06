module IO
  module ByteFormat
    module BigEndian
      extend ByteFormat
    end
  end
end

@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

def accepts(format : IO::ByteFormat) : Int32
  66
end

C.putchar(accepts(IO::ByteFormat::BigEndian))
C.putchar(10)
