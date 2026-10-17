@[Link(ldflags: "@@OUT_HELPER_OBJECT@@")]
lib OutContractInvalid
  fun scalar = adamas_out_contract_scalar(value : Int32) : Int32
end

OutContractInvalid.scalar(out value)
