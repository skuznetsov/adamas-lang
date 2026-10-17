@[Link("c")]
lib LocalReturnSummaryContractOutput
  fun getpid : Int32
  fun putchar(value : Int32) : Int32
end

def local_return_summary_contract_exhaustive
  if LocalReturnSummaryContractOutput.getpid < 0
    x = 2
  else
    x = 1
  end
  return x
end

z = local_return_summary_contract_exhaustive
if z.is_a?(Nil)
  LocalReturnSummaryContractOutput.putchar(50)
  LocalReturnSummaryContractOutput.putchar(48)
else
  LocalReturnSummaryContractOutput.putchar(48 &+ z)
end
LocalReturnSummaryContractOutput.putchar(10)
