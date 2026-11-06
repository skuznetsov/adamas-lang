lib LibC
  fun putchar(value : Int32) : Int32
end

module ForallFormalOwner(T)
  def emit(value : T) forall T
    LibC.putchar(value)
  end
end

class ForallFormalHost
  include ForallFormalOwner(Bool)
end

ForallFormalHost.new.emit(65)
LibC.putchar(10)
