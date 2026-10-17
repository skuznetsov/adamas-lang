lib OutDeclarationProbe
  fun strtol(input : UInt8*, end_ptr : UInt8**, base : Int32) : Int64
end
OutDeclarationProbe.strtol("1".to_unsafe, out tail, 10)
OutDeclarationProbe.strtol("2".to_unsafe, out tail, 10)
