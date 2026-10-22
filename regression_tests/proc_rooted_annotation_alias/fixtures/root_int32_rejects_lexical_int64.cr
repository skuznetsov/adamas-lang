require "proc"
alias SourceAlias = Int32
module ProcSourceOwner
  alias SourceAlias = Int64
  def self.make
    ->(value : ::SourceAlias) : ::SourceAlias { value }
  end
end
ProcSourceOwner.make.call(65_i64)
