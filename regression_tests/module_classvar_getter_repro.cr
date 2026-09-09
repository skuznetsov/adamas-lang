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
end

LibC.exit(NPModule.enabled? ? 0 : 17)
