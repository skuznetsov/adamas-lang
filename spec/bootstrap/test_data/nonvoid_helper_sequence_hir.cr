class GenericIfCallSequence(T)
  @entries : Pointer(Int32)

  def initialize
    @entries = Pointer(Int32).null
  end

  def malloc_entries(size)
    Pointer(Int32).malloc(size)
  end

  private def upsert(key, value) : Int32?
    if @entries.null?
      @entries = malloc_entries(4)
    end

    hash = key
    hash
  end

  def run : Int32
    upsert(42, 7).as(Int32)
  end
end

GenericIfCallSequence(Int32).new.run
