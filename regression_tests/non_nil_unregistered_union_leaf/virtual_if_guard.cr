lib LibC
  fun exit(status : Int32) : NoReturn
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
    4
  end
end

class Table
  def unsafe_fetch(index : Int) : Int32
    index &* 10
  end

  def lookup(finder : Finder)
    if index = finder.find
      unsafe_fetch(index)
    else
      7
    end
  end
end

finders = {NoneFinder.new.as(Finder), SomeFinder.new.as(Finder)}
t = Table.new
LibC.exit(t.lookup(finders[0]) &+ t.lookup(finders[1]))
