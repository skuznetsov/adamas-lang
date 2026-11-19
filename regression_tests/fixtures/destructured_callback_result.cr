lib LibC
  fun putchar(value : Int32) : Int32
end

abstract class DestructuredEntry
end

class DestructuredLeaf < DestructuredEntry
end

class DestructuredResult(T)
end

module DestructuredCallback(T)
  def transform(& : T -> U) : DestructuredResult(U) forall U
    result = DestructuredResult(U).new
    yield({7, true})
    result
  end
end

class DestructuredReceiver
  include DestructuredCallback(Tuple(Int32, Bool))
end

def transform_explicit(& : Tuple(Int32, Bool) -> U) : DestructuredResult(U) forall U
  result = DestructuredResult(U).new
  yield({7, true})
  result
end

def transform_reference(& : Tuple(DestructuredEntry, Bool) -> U) : DestructuredResult(U) forall U
  result = DestructuredResult(U).new
  yield({DestructuredLeaf.new, true})
  result
end

def int_tag(result : DestructuredResult(Int32))
  65
end

def bool_tag(result : DestructuredResult(Bool))
  66
end

def entry_tag(result : DestructuredResult(DestructuredEntry))
  67
end

def leaf_tag(result : DestructuredResult(DestructuredLeaf))
  68
end

receiver = DestructuredReceiver.new
LibC.putchar(int_tag(receiver.transform { |number, flag| number }))
LibC.putchar(bool_tag(receiver.transform { |number, flag| flag }))
LibC.putchar(int_tag(transform_explicit { |number, flag| number }))
LibC.putchar(entry_tag(transform_reference { |entry, flag| entry }))
LibC.putchar(10)
