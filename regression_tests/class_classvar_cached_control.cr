lib LibC
  fun exit(status : Int32) : Nil
end

class NPClass
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

first = NPClass.enabled?
second = NPClass.enabled?
if first
  if second
    NPClass.disable
    third = NPClass.enabled?
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
