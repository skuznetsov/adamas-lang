lib LibC
  fun exit(status : Int32) : Nil
end

module NPModule
  @@enabled : Bool? = nil

  def self.enabled? : Bool
    cached = @@enabled
    return cached unless cached.nil?
    value = true
    @@enabled = value
    value
  end

  def self.disable : Nil
    @@enabled = false
  end
end

first = NPModule.enabled?
second = NPModule.enabled?
if first
  if second
    NPModule.disable
    third = NPModule.enabled?
    if third
      LibC.exit(31)
    end
    LibC.exit(0)
  else
    LibC.exit(32)
  end
else
  LibC.exit(33)
end
