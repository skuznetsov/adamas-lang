lib LibC
  fun exit(status : Int32) : NoReturn
end

class EmptyNamedCollectionExplicitProbe(T)
  def initialize
  end
end

probe = EmptyNamedCollectionExplicitProbe(Int32){}
LibC.exit(0)
