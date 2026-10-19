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

lib ModuleIdentityProbe
  fun putchar(value : Int32) : Int32
end

def emit(value : FirstEnumNamespace::Code)
  ModuleIdentityProbe.putchar(65)
end

def emit(value : SecondEnumNamespace::Code)
  ModuleIdentityProbe.putchar(66)
end

emit(FirstEnumNamespace::Code::Marker)
emit(SecondEnumNamespace::Code::Marker)
