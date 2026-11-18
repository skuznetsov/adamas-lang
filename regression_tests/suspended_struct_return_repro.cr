lib C
  fun putchar(code : Int32) : Int32
end
struct ResultIndex
  def initialize(@code : Int32)
  end
  def code
    @code
  end
end
struct RescuePart
  def initialize(@first : ResultIndex)
  end
  def first
    @first
  end
end
class ParserLike
  BASE = ResultIndex.new(65)
  def initialize(@again : Bool, @walk : Bool)
    @scope = false
  end
  def scoped(&)
    old = @scope
    @scope = true
    result = yield
    @scope = old
    result
  end
  def statement : ResultIndex
    scoped { in_scope }
  end
  def in_scope : ResultIndex
    unless @again
      return BASE
    end
    unless @walk
      @again = false
      return sections.first
    end
    @walk = false
    body
  end
  def sections : RescuePart
    C.putchar(82)
    RescuePart.new(statement)
  end
  def body : ResultIndex
    if @scope
      sections.first
    else
      statement
    end
  end
  def entry0
    entry1
  end
  def entry1
    entry2
  end
  def entry2
    entry3
  end
  def entry3
    entry4
  end
  def entry4
    statement
  end
end
C.putchar(ParserLike.new(true, true).entry0.code)
C.putchar(ParserLike.new(false, false).entry0.code)
C.putchar(10)
