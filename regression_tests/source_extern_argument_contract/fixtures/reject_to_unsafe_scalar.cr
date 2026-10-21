struct BadScalar
  def to_unsafe : Int32
    1_i32
  end
end
lib C
  fun free(value : UInt8*)
end
C.free(BadScalar.new)
