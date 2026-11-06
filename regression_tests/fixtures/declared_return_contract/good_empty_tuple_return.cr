@[Link("gc")]
lib ReturnExit
  fun exit(code : Int32) : NoReturn
end
def result : Tuple()
  ReturnExit.exit(0)
end
result
