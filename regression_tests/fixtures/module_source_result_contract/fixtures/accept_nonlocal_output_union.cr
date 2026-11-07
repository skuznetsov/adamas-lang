@[Link("c")]
lib InlineForallNonlocalControlC
  fun putchar(value : Int32) : Int32
end

class InlineForallNonlocalEntry
end

def output_only(&block : -> T) : T forall T
  yield
end

def input_bound(value : T, &block : -> T) : T forall T
  yield
end

def accept_nonlocal_output_union(class_side : Bool, escape : Bool) : Nil
  output_only do
    return nil if escape
    if class_side
      InlineForallNonlocalEntry
    else
      InlineForallNonlocalEntry.new
    end
  end
  InlineForallNonlocalControlC.putchar(65)
end

def accept_nonlocal_input_bound(escape : Bool) : Nil
  input_bound(InlineForallNonlocalEntry.new) do
    return nil if escape
    InlineForallNonlocalEntry.new
  end
  InlineForallNonlocalControlC.putchar(66)
end

accept_nonlocal_output_union(false, false)
accept_nonlocal_input_bound(false)
InlineForallNonlocalControlC.putchar(10)
