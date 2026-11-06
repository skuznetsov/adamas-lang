require "./cross_file_nil/macros"

macro forward_nil
  classify(nil)
end

forward_nil
LibC.putchar(10)
