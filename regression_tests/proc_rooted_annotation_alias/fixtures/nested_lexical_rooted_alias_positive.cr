require "proc"
lib ProcSourceIdentityOutput
  fun putchar(value : Int32) : Int32
end
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
if ProcSourceOuter::Inner.make.call(67_u8) == 67_u8
  ProcSourceIdentityOutput.putchar(67_i32)
end
ProcSourceIdentityOutput.putchar(10_i32)
