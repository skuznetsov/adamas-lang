lib LibC
  fun putchar(value : Int32) : Int32
end

class GenericReopenBehaviorParent(T)
  def marker : Int32
    65_i32
  end
end

class GenericReopenBehaviorChild < GenericReopenBehaviorParent(Int32)
end

class GenericReopenBehaviorChild < GenericReopenBehaviorParent(Int32)
end

LibC.putchar(GenericReopenBehaviorChild.new.marker)
