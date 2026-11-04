def relay(input : U, &block : -> U) forall U
  block.call
end

relay(1) { true }
