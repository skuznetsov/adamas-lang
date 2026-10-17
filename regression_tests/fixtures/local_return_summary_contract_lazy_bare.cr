@[Link("c")]
lib LocalReturnSummaryContractOutput
  fun getpid : Int32
  fun putchar(value : Int32) : Int32
end

def local_return_summary_contract_yield(value : Int32)
  yield value
end

def local_return_summary_contract_bar
  local_return_summary_contract_yield(1) do |b|
    if LocalReturnSummaryContractOutput.getpid < 0 || b == 0
      x = 10
    end

    return x
  end
end

z = local_return_summary_contract_bar
if z.is_a?(Nil)
  LocalReturnSummaryContractOutput.putchar(50)
  LocalReturnSummaryContractOutput.putchar(48)
else
  LocalReturnSummaryContractOutput.putchar(48 &+ z)
end
LocalReturnSummaryContractOutput.putchar(10)
