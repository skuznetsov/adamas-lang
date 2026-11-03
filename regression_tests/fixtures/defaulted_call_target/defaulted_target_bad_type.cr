module DefaultedReject
  def self.value(seed : Int32, *, payload : Int32 = 0_i32) : Int32
    65_i32
  end
end
DefaultedReject.value(4294967296_i64)
