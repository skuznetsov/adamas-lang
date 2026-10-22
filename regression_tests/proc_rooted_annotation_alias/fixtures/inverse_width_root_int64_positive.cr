require "proc"
lib ProcSourceIdentityOutput
  fun putchar(value : Int32) : Int32
end
alias SourceAlias = Int64
module ProcSourceOwner
  alias SourceAlias = Int32
  def self.make
    ->(value : ::SourceAlias) : ::SourceAlias { value }
  end
end
if ProcSourceOwner.make.call(66_i64) == 66_i64
  ProcSourceIdentityOutput.putchar(66_i32)
end
ProcSourceIdentityOutput.putchar(10_i32)
