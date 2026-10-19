module FirstEnumNamespace
  enum Code : UInt8
    Marker = 7_u8
  end
end

module SecondEnumNamespace
  enum Code : UInt8
    Marker = 7_u8
  end
end

def accepts_first(value : FirstEnumNamespace::Code)
end

accepts_first(SecondEnumNamespace::Code::Marker)
