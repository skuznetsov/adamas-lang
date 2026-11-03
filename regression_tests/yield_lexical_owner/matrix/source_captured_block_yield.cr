def capture_block_as_value(&callback : -> Int32) : Int32
  callback.call
end

def forward_to_captured_block(&callback : -> Int32) : Int32
  capture_block_as_value { yield }
end

forward_to_captured_block { 65 }
