@[Extern]
lib LibC
  fun exit(status : Int32) : NoReturn
end

i = 0
until i == 3
  i += 1
end

LibC.exit(i == 3 ? 0 : 1)
