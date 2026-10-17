@[Link(ldflags: "@@OUT_HELPER_OBJECT@@")]
lib OutContractInvalid
  fun variadic = adamas_out_contract_variadic(prefix : Int32, ...) : Int32
end

OutContractInvalid.variadic(1, out value)
