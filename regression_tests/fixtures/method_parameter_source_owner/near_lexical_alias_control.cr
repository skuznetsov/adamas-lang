lib LibC
  fun putchar(c : Int32) : Int32
end

module NearScope
  alias Type = Int32

  class Holder
    def self.emit(value : Type)
      LibC.putchar(value)
    end
  end
end

NearScope::Holder.emit(65)
LibC.putchar(10)
