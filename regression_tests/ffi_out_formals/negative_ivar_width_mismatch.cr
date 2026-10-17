@[Link(ldflags: "@@OUT_HELPER_OBJECT@@")]
lib OutContractInvalid
  fun fill_u32 = adamas_out_contract_fill_u32(value : UInt32*) : Int32
end

class OutContractBadHolder
  @count : Int32

  def initialize
    OutContractInvalid.fill_u32(out @count)
  end
end

OutContractBadHolder.new
