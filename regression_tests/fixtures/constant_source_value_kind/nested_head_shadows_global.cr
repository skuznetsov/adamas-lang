lib Native
 fun putchar(value : Int32) : Int32
end
module Head
 Value = 66
end
module App
 module Head
 Value = 65
 end
 def self.run
 Head::Value
 end
end
Native.putchar(App.run)
