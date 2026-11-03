class DefaultedConstructorRejectOwner
  def initialize(@pointer : Int64, @size : Int32, @read_only : Bool)
  end

  def self.new(size : Int32, *, read_only = false) : Int32
    read_only ? 66_i32 : 65_i32
  end
end

DefaultedConstructorRejectOwner.new(4294967296_i64)
