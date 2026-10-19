module FirstEnumNamespace
  enum Code : UInt8
    Marker = 7_u8
  end
end

def accepts_enum(value : FirstEnumNamespace::Code)
end

accepts_enum(7_u8)
