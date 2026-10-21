lib ActiveParentOracleLib
  fun putchar(value : Int32) : Int32
end

abstract struct ActiveAbstractStruct
  struct Child < ActiveAbstractStruct
    def marker : Int32
      65
    end
  end
end

ActiveParentOracleLib.putchar(ActiveAbstractStruct::Child.new.marker)
