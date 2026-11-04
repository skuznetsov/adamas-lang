lib LibC
  fun exit(status : Int32) : NoReturn
end

class Consumer
  def run
    LibC.exit(1) unless apply(7, ->(input : Int32) { input }) == 7
    LibC.exit(2) unless apply(2147483649_i64, ->(input : Int64) { input }) == 2147483649_i64
    LibC.exit(3) unless apply(7, ->convert(Int32)) == 2147483651_i64
  end

  private def convert(value : Int32)
    2147483651_i64
  end

  private def apply(value, transform : Proc)
    transform.call(value)
  end
end

Consumer.new.run
LibC.exit(0)
