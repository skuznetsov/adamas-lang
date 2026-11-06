@[Link("c")]
lib LibC
  fun putchar(value : Int32) : Int32
  fun getpid : Int32
  fun abort : NoReturn
end
fun __crystal_personality(version : Int32, actions : Int32, cls : UInt64, ex : Void*, ctx : Void*) : Int32
  LibC.abort
end
fun __crystal_get_exception(ex : Void*) : UInt64
  LibC.abort
end
fun __crystal_raise(ex : Void*) : NoReturn
  LibC.abort
end
fun __crystal_raise_overflow : NoReturn
  LibC.abort
end
class Context
  def value : Int32
    65
  end
end
class Flag
  def self.enabled? : Bool
    LibC.getpid > 0
  end
end
class Writer
  @value : Int32 = if Flag.enabled?; 65; else 66; end
  def value : Int32
    @value
  end
end
class Controller
  def get(&block : Context, Int32 -> Context) : Context
    block.call(Context.new, 0)
  end
  def log(&)
    yield
  end
  def memory(&)
    bytes_before_measure = 23
    yield
    bytes_before_measure
  end
  def measure(&block : ->)
    start = 17
    yield
    start
  end
  def report(io : Int32, &)
    mem = 0
    elapsed = measure do
      mem = memory do
        begin
          yield
        rescue
          log { 0 }
        end
      end
    end
    io
  end
  def install(flag : Bool)
    get do |context, _|
      report(context.value) do
        writer = -> do
          nested_writer = Writer.new
          value = nested_writer.value
          LibC.putchar(value)
          value
        end
        writer.call
      end
      context
    end
  end
end
LibC.putchar(Controller.new.install(false).value)
LibC.putchar(10)
