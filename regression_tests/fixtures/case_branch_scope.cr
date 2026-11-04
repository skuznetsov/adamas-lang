lib LibC
  fun exit(status : Int32) : NoReturn
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
  def initialize(@choose_when : Bool)
  end

  def run(&) : Nil
    yield
    case
    when @choose_when
      IntConsumer.new.consume(WHEN_ARG)
    else
      IntConsumer.new.consume(ELSE_ARG)
    end
    nil
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

LibC.exit(exercise(Runner.new(true)) == 1 &&
          exercise(Runner.new(false)) == 1 &&
          exercise(AnotherRunner.new) == 1 ? 0 : 1)
