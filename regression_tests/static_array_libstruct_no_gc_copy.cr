# The StaticArray(C-struct) IndexGet branch synthesizes a copied value in LLVM.
# `--no-gc` must see that backend allocation even though HIR contains no explicit
# allocator operation.
lib StaticArrayNoGcProbe
  struct Cell
    value : Int32
  end

  fun putchar(value : Int32) : Int32
end

cells = uninitialized StaticArrayNoGcProbe::Cell[1]
initialized = uninitialized StaticArrayNoGcProbe::Cell
initialized.value = 0
cells[0] = initialized
StaticArrayNoGcProbe.putchar(cells[0].value + 48)
StaticArrayNoGcProbe.putchar(10)
