lib C
  fun putchar(value : Int32) : Int32
end

class ModuleSourcePacketLeft
  def code : Int32
    65
  end
end

class ModuleSourcePacketRight
  def code : Int32
    66
  end
end

module ModuleSourcePacketFactory
  def self.implicit(flag : Bool) : ModuleSourcePacketLeft | ModuleSourcePacketRight
    if flag
      ModuleSourcePacketLeft.new
    else
      ModuleSourcePacketRight.new
    end
  end

  def self.explicit(flag : Bool) : ModuleSourcePacketLeft | ModuleSourcePacketRight
    if flag
      return ModuleSourcePacketLeft.new
    end
    return ModuleSourcePacketRight.new
  end
end

implicit_value = ModuleSourcePacketFactory.implicit(true)
C.putchar(implicit_value.code)
explicit_value = ModuleSourcePacketFactory.explicit(false)
C.putchar(explicit_value.code)
C.putchar(10)
