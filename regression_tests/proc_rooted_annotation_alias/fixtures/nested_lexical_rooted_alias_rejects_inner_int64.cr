require "proc"
alias SourceAlias = UInt8
module ProcSourceOuter
  alias SourceAlias = Int16
  module Inner
    alias SourceAlias = Int64
    def self.make
      ->(value : ::SourceAlias) : ::SourceAlias { value }
    end
  end
end
ProcSourceOuter::Inner.make.call(67_i64)
