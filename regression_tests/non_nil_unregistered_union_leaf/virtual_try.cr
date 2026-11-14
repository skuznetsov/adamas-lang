lib LibC
  fun exit(status : Int32) : NoReturn
end

class Object
  def try(&)
    yield self
  end
end

struct Nil
  def try(&)
    self
  end
end

abstract class Finder
  abstract def find : Int32?
end

class NoneFinder < Finder
  def find : Int32?
    nil
  end
end

class SomeFinder < Finder
  def find : Int32?
    3
  end
end

class Table
  def unsafe_fetch(index : Int) : Int32
    index &* 10
  end

  def lookup(finder : Finder)
    finder.find.try { |index| unsafe_fetch(index) }
  end
end

finders = {NoneFinder.new.as(Finder), SomeFinder.new.as(Finder)}
t = Table.new
a = t.lookup(finders[0])
b = t.lookup(finders[1])
LibC.exit(a.nil? && b ? b : 99)
