lib LogBuilderProbeOutput
  fun putchar(value : Int32) : Int32
end

struct Nil
  def try(&)
    self
  end
end

class LogBuilderProbeEntry
end

class LogBuilderProbeRef(T)
  @target : T?

  def initialize(@target : T?)
  end

  def value
    @target.as(T?)
  end

  def try(&)
    yield self
  end
end

class LogBuilderProbeCache(T)
  @ref : LogBuilderProbeRef(T)?

  def initialize(@ref : LogBuilderProbeRef(T)?)
  end

  def []?(key : Int32) : LogBuilderProbeRef(T)?
    @ref
  end

  def []=(key : Int32, ref : LogBuilderProbeRef(T))
    @ref = ref
  end
end

class LogBuilderProbeLock
  def synchronize(& : -> _)
    yield
  end
end

class LogBuilderProbeBindings
  def each(& : -> _)
    yield
  end
end

def observe_entry(entry : LogBuilderProbeEntry) : Nil
  nil
end

class LogBuilderProbeBuilder
  @logs : LogBuilderProbeCache(LogBuilderProbeEntry)
  @bindings : LogBuilderProbeBindings
  @mutex : LogBuilderProbeLock

  def initialize
    @logs = LogBuilderProbeCache(LogBuilderProbeEntry).new(nil)
    @bindings = LogBuilderProbeBindings.new
    @mutex = LogBuilderProbeLock.new
  end

  def for : LogBuilderProbeEntry
    if cached_ref = @logs[0_i32]?
      cached_ref.value
    end
    @mutex.synchronize do
      log = @logs[0_i32]?.try &.value

      if log.nil?
        log = LogBuilderProbeEntry.new
        @bindings.each do
          observe_entry(log)
        end
        @logs[0_i32] = LogBuilderProbeRef(LogBuilderProbeEntry).new(log)
      end

      log
    end
  end
end

LogBuilderProbeBuilder.new.for
LogBuilderProbeOutput.putchar(75_i32)
LogBuilderProbeOutput.putchar(10_i32)
