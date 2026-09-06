lib LibC
  fun exit(status : Int32) : NoReturn
end

class EmptyNamedCollectionProbe(T)
  def initialize
  end
end

probe = EmptyNamedCollectionProbe{}
LibC.exit(probe.object_id.to_i32)
