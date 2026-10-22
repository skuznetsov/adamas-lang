require "proc"
alias SourceAlias = Int64
module ProcSourceOwner
  alias SourceAlias = Int32
  def self.make
    ->(value : ::SourceAlias) : ::SourceAlias { value }
  end
end
ProcSourceOwner.make.call(65_i32)
