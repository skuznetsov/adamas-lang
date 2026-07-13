class Hash(K, V)
  @entries : Pointer(Entry(K, V))

  def get_entry(index : Int32) : Entry(K, V)
    @entries[index]
  end

  struct Entry(K, V)
    def initialize(@key : K, @value : V)
    end
  end
end

def exercise(table : Hash(String, Nil))
  table.get_entry(0)
end

exercise(uninitialized Hash(String, Nil))
