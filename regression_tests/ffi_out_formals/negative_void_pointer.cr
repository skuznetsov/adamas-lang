@[Link(ldflags: "@@OUT_HELPER_OBJECT@@")]
lib OutContractInvalid
  fun opaque = adamas_out_contract_opaque(value : Void*) : Int32
end

OutContractInvalid.opaque(out value)
