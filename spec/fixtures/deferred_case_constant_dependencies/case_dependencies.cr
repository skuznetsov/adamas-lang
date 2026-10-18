module CaseDependenciesInsideDeferredCall
  def self.capture(value : Int32) : Int32
    value
  end

  SUBJECT = capture(case ARGV.size
  when 0
    10
  else
    20
  end)

  CONDITION = capture(case 0
  when ARGV.size
    11
  else
    12
  end)

  BRANCH_BODY = capture(case 0
  when 0
    ARGV.size
  else
    20
  end)

  ELSE_BODY = capture(case 0
  when 1
    10
  else
    ARGV.size
  end)
end

STDOUT.puts CaseDependenciesInsideDeferredCall::SUBJECT
STDOUT.puts CaseDependenciesInsideDeferredCall::CONDITION
STDOUT.puts CaseDependenciesInsideDeferredCall::BRANCH_BODY
STDOUT.puts CaseDependenciesInsideDeferredCall::ELSE_BODY
