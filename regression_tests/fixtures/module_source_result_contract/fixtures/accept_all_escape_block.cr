lib Native
  fun putchar(value : Int32) : Int32
end

def relay(&block : -> T) : T forall T
  yield
end

def exercise : Int32
  relay { return 65 }
  66
end

Native.putchar(exercise)
Native.putchar(10)
