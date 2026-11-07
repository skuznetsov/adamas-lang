class InlineForallNonlocalRejectEntry
end

def input_bound(value : T, &block : -> T) : T forall T
  yield
end

def reject_nonlocal_input_bound_mixed(class_side : Bool, escape : Bool) : Nil
  input_bound(InlineForallNonlocalRejectEntry.new) do
    return nil if escape
    if class_side
      InlineForallNonlocalRejectEntry
    else
      InlineForallNonlocalRejectEntry.new
    end
  end
end

reject_nonlocal_input_bound_mixed(false, false)
