module FirstNamespace
  enum Code : UInt8
    Marker = 7_u8
  end
end

module SecondNamespace
  enum Code : UInt8
    Marker = 7_u8
  end
end

def accepts_first(value : FirstNamespace::Code)
end

accepts_first(SecondNamespace::Code::Marker)
