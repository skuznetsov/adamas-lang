lib LibC
  fun putchar(value : Int32) : Int32
end

abstract class RowValue
end

class RowOwner
end

class FieldRow < RowValue
  def initialize(@number : Int32, @owner : RowOwner)
  end
end

class OtherRow < RowValue
end

class ResultBox(T)
end

def collect(& : Int32 -> T) forall T
  result = ResultBox(T).new
  yield 42
  result
end

def row_tag(result : ResultBox(RowValue))
  65
end

def show(owner : RowOwner)
  LibC.putchar(row_tag(collect { |number| FieldRow.new(number, owner).as(RowValue) }))
  LibC.putchar(10)
end

show(RowOwner.new)
