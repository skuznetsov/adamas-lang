lib CallbackBoundaryC
  fun before(Int32) : Int32
  fun set_callback(Void*, (Int32, Int32) -> Int32)
  fun after(Int32) : Int32
end
