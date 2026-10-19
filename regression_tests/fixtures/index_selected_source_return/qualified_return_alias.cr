lib IndexAliasProbeC
  fun putchar(value : Int32) : Int32
end

struct Slice(T)
  def initialize(@element : T)
  end
end

module QualifiedIndexAlias
  alias Result = Slice(UInt8)
end

class QualifiedAliasIndex
  def [](start : Int32, count : Int32) : QualifiedIndexAlias::Result
    QualifiedIndexAlias::Result.new(67_u8)
  end
end

def accept_slice(value : Slice(UInt8)) : Int32
  67
end

IndexAliasProbeC.putchar(accept_slice(QualifiedAliasIndex.new[0, 1]))
