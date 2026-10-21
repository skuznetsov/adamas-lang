lib LibC
  fun putchar(value : Int32) : Int32
end

module StructNamespace
  abstract struct Parent
    def marker : Int32
      67_i32
    end
    struct Child < Parent
    end
  end
end
LibC.putchar(StructNamespace::Parent::Child.new.marker)
