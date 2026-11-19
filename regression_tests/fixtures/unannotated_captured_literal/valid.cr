lib Native
  fun putchar(value : Int32) : Int32
end

class CapturedTicket
  def initialize(&@run : ->)
  end

  def run : Nil
    @run.call
  end
end

def dispatch_job(*, priority : Int32 = 1, urgent : Bool = false, &job)
  CapturedTicket.new(&job)
end

a = 65
b = 66
c = 67
first = dispatch_job(urgent: true) { Native.putchar(a); 17 }
second = dispatch_job(urgent: false) { Native.putchar(b); false }
third = dispatch_job(priority: 2) { Native.putchar(c); 18_i64 }
first.run
second.run
third.run
Native.putchar(10)
