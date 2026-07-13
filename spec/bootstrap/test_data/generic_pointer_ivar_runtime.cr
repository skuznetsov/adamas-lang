lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

class Hash(K, V)
  @entries : Pointer(Entry(K, V))

  def initialize(@entries : Pointer(Entry(K, V)))
  end

  def get_entry(index : Int32) : Entry(K, V)
    @entries[index]
  end

  struct Entry(K, V)
    def initialize(@tag : Int32)
    end

    def tag : Int32
      @tag
    end
  end
end

def verify_generic_pointer_ivar : Nil
  entries = Pointer(Hash::Entry(String, Nil)).malloc(1)
  entries[0] = Hash::Entry(String, Nil).new(73)
  table = Hash(String, Nil).new(entries)

  if table.get_entry(0).tag == 73
    LibC.printf("ADAMAS_GENERIC_POINTER_IVAR_OK\n")
  end
end

verify_generic_pointer_ivar
