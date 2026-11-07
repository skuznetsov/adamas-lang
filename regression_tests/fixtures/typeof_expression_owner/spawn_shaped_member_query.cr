lib Native
  fun putchar(c : Int32) : Int32
end
class Config
  def initialize(@port : Int32); end
  def port : Int32; @port; end
end
class Service
  def initialize(@config : Config); end
  def run
    work = ->(port : typeof(@config.port), enabled : typeof(true),) {
      Native.putchar(port) if enabled
    }
    work.call(65, true)
  end
end
Service.new(Config.new(65)).run
