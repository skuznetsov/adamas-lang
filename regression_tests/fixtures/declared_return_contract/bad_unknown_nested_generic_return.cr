@[Link("gc")]
lib ReturnExit
  fun exit(code : Int32) : NoReturn
end
def result : Tuple(MissingReturnLeaf)
  ReturnExit.exit(0)
end
result
