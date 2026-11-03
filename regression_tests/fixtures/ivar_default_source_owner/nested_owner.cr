lib LibC
  fun putchar(value : Int32) : Int32
end
module App
  class Config
    DEFAULT_LEVEL = 66
    module Options
      DEFAULT_LEVEL = 65
      @level : Int32 = DEFAULT_LEVEL
      def level : Int32; @level; end
    end
    include Options
  end
end
LibC.putchar(App::Config.new.level)
LibC.putchar(10)
