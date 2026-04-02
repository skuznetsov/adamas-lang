@[Extern]
lib LibC
  fun exit(status : Int32) : NoReturn
end

class Mini
  def each_pair(&)
    i = 0
    while i < 2
      yield i + 1, i
      i += 1
    end
  end

  def find : Int32?
    each_pair do |value, index|
      return index if value == 2
    end
    nil
  end
end

result = Mini.new.find
LibC.exit(result == 1 ? 0 : 1)
