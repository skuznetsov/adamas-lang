lib C
  fun atexit(callback : -> Nil) : Int32
  fun exit(status : Int32) : NoReturn
end
def raise(message : String) : NoReturn
  C.exit(93)
end
C.atexit(-> { 7_i32 })
