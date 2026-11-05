lib Native
 fun putchar(value : Int32) : Int32
end
Thing = 7
module App
 class Thing
 end
 def self.accept(value : Thing.class)
 65
 end
 def self.run
 accept(Thing)
 end
end
Native.putchar(App.run)
