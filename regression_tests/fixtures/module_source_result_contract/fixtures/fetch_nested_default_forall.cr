lib C
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
end
class Entry
  def code : Int32
    65
  end
end
module Store
  def self.get(flag : Bool) : Entry?
    if flag
      Entry.new
    end
  end
end
def fetch(flag, default : T) : Entry | T forall T
  fetch(flag) { default }
end
def fetch(flag : Bool, &block : -> T) : Entry | T forall T
  if value = Store.get(flag)
    value
  else
    yield
  end
end
value = fetch(C.getpid > 0, nil)
if value
  C.putchar(value.code)
end
C.putchar(10)
