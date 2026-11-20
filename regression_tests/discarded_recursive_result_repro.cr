lib Native
  fun putchar(value : Int32) : Int32
end

class Table
  def value : Int32
    5
  end
end

class VisitChildren
  def each(value : Int32)
    if value > 0
      yield value &- 1
    end
    self
  end
end

class Collector
  @table = Table.new
  @children = VisitChildren.new
  @visits = 0

  def visits : Int32
    @visits
  end

  def cli(value : Int32) : Int32
    run_check(value)
  end

  private def run_check(value : Int32) : Int32
    code = parse(value)
    collect_symbols(code).table.value
  end

  private def parse(value : Int32) : Int32
    scan(value)
  end

  private def scan(value : Int32) : Int32
    value
  end

  private def collect_symbols(value : Int32) : self
    collect(value)
    overlay
    self
  end

  def table : Table
    @table
  end

  private def overlay : Table
    @table
  end

  private def collect(value : Int32) : self
    root(value)
    self
  end

  private def root(value : Int32) : Bool
    visit(value)
    true
  end

  def result(value : Int32) : Int32
    if symbol = visit(value)
      symbol.value
    else
      0
    end
  end

  private def visit(value : Int32)
    @visits &+= 1
    return if value < 1
    if value > 2
      visit(value &- 1)
    elsif value == 2
      handle_class(value)
    else
      handle_def(value)
    end
  end

  private def handle_def(value : Int32)
    @children.each(value) do |child|
      visit(child)
    end
    pop_table
  end

  private def handle_class(value : Int32)
    collect_class_body(value)
    pop_table
  end

  private def collect_class_body(value : Int32)
    @children.each(value) do |child|
      expand_accessor(child)
    end
  end

  private def expand_accessor(value : Int32)
    @children.each(value) do |child|
      visit(child)
    end
  end

  private def pop_table
    table
  end
end

collector = Collector.new
Native.putchar(48 &+ collector.cli(3))
Native.putchar(48 &+ collector.visits)
Native.putchar(48 &+ collector.result(3))
Native.putchar(48 &+ collector.result(0))
Native.putchar(48 &+ collector.result(1))
Native.putchar(10)
