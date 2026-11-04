lib LibC
  fun exit(status : Int32) : NoReturn
end

def loop
  while true
    yield
  end
end

struct Int32
  def times(&)
    index = 0
    while index < self
      yield index
      index &+= 1
    end
    self
  end
end

module Accept(T)
  def consume(value : T)
    value
  end
end

class IntConsumer
  include Accept(Int32)
end

class Runner
  def run(&) : Nil
    yield
    LOOP_HEADER
      IntConsumer.new.consume(CALL_ARGUMENT)
      break
    end
  end
end

class AnotherRunner
  def run(&) : Nil
    yield
  end
end

def exercise(runner : Runner | AnotherRunner)
  seen = 0
  runner.run do
    seen = 1
  end
  seen
end

LibC.exit(exercise(Runner.new) == 1 && exercise(AnotherRunner.new) == 1 ? 0 : 1)
