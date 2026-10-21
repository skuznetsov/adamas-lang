struct Payload
end
lib C
  fun free(value : Void*)
end
C.free(Payload.new)
