@[Link("c")]
lib LocalReturnSummaryContractOutput
  fun putchar(value : Int32) : Int32
end

def local_return_summary_contract_recursive(n : Int32)
  x = n
  if n > 0
    return local_return_summary_contract_recursive(n &- 1)
  end
  return x
end

z = local_return_summary_contract_recursive(1)
if z.is_a?(Nil)
  LocalReturnSummaryContractOutput.putchar(50)
  LocalReturnSummaryContractOutput.putchar(48)
else
  LocalReturnSummaryContractOutput.putchar(48 &+ z)
end
LocalReturnSummaryContractOutput.putchar(10)
