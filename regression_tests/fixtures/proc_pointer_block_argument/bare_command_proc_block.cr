lib ProcBlockC
  fun putchar(value : Int32) : Int32
end
class Walker
  def each(&block : Int32 -> Nil) : Nil
    yield 65
    nil
  end
  def accept(value : Int32) : Nil
    ProcBlockC.putchar(value)
    nil
  end
  def run_bare : Nil
    each &->self.accept(Int32)
    nil
  end
end
Walker.new.run_bare
