lib LibC
  fun putchar(value : Int32) : Int32
end
def alias_identity(value : LaterMethodAlias) : LaterMethodAlias
  value
end
alias LaterMethodAlias = Int32
LibC.putchar(alias_identity(65_i32))
