require "proc"
lib ProcSourceIdentityOutput
  fun putchar(value : Int32) : Int32
end
alias SourceAlias = Int32
module ProcSourceOwner
  alias SourceAlias = Int64
  def self.make
    ->(value : ::SourceAlias) : ::SourceAlias { value }
  end
end
ProcSourceIdentityOutput.putchar(ProcSourceOwner.make.call(65_i32))
ProcSourceIdentityOutput.putchar(10_i32)
