class ArenaA
  @data : Int32
  def initialize(@data) end
  def get; @data; end
end

class ArenaB
  @data : Int32
  def initialize(@data) end
  def get; @data; end
end

alias ArenaLike = ArenaA | ArenaB

class Container
  @arena : ArenaLike
  @other : Int32
  def initialize(@arena, @other) end

  def with_arena(&)
    old = @arena
    yield
    @arena = old
  end

  def call_in_block
    with_arena do
      @arena.get
    end
  end
end

lib LibC
  fun exit(status : Int32) : NoReturn
end

c = Container.new(ArenaA.new(42), 99)
result = c.call_in_block
if result == 42
  LibC.exit(0)
end
LibC.exit(1)
