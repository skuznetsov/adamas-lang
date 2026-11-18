lib LibC
  fun putchar(value : Int32) : Int32
end

class Entry
  def initialize(@value : Int32)
  end

  def code
    @value
  end

  def loop(delta : Int32)
    @value &+ delta
  end
end

def local(loop : Int32)
  loop
end

def member(loop : Entry)
  loop.code
end

def assignment
  if loop = Entry.new(67)
    loop.code
  else
    90
  end
end

def loop(delta : Int32)
  delta &+ 1
end

def loop(&)
  while true
    yield
  end
end

LibC.putchar(local(65))
LibC.putchar(member(Entry.new(66)))
LibC.putchar(assignment)
LibC.putchar(loop(67))
LibC.putchar(Entry.new(68).loop(1))
i = 0
loop do
  i = i &+ 1
  break if i == 2
end
LibC.putchar(68 &+ i)
loop { LibC.putchar(71); break }
LibC.putchar(10)
