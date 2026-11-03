lib LibC
  fun putchar(c : Int32) : Int32
end

module DeferredPathConstantAliasUnionProbe
  def self.maybe(flag : Bool) : Int32?
    if flag
      65
    else
      nil
    end
  end

  SOURCE = maybe(false)
  ALIAS = DeferredPathConstantAliasUnionProbe::SOURCE

  def self.consume(value : Int32) : Int32
    value
  end
end

LibC.putchar(DeferredPathConstantAliasUnionProbe.consume(DeferredPathConstantAliasUnionProbe::ALIAS))
