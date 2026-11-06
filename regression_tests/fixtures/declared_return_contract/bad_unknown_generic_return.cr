@[Link("gc")]
lib ReturnExit
  fun exit(code : Int32) : NoReturn
end
def result : MissingReturnBox(Int32)
  ReturnExit.exit(0)
end
result
