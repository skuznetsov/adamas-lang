lib LibC
  fun exit(code : Int32) : NoReturn
end

module Metadata
  alias Entry = {key: Int32, value: {Int64, UInt8}}
  alias Positional = {Int32, Int64}

  def self.named(entry : Entry) : Bool
    entry[:key] == 23 && entry[:value][0] == 91_i64 && entry[:value][1] == 7_u8
  end

  def self.positional(entry : Positional) : Bool
    entry[0] == 14 && entry[1] == 19_i64
  end
end

LibC.exit(1) unless Metadata.named({key: 23, value: {91_i64, 7_u8}})
LibC.exit(2) unless Metadata.positional({14, 19_i64})
LibC.exit(3) unless Metadata.named({value: {91_i64, 7_u8}, key: 23})
LibC.exit(0)
