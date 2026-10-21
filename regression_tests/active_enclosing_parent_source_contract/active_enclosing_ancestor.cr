lib LibC
  fun putchar(value : Int32) : Int32
end

module ActiveNamespace
  class Grandparent
    def marker : Int32
      66_i32
    end
    class Middle
      class Child < Grandparent
      end
    end
  end
end
LibC.putchar(ActiveNamespace::Grandparent::Middle::Child.new.marker)
