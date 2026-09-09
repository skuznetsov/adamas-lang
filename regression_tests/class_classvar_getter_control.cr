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
end

LibC.exit(NPClass.enabled? ? 0 : 17)
