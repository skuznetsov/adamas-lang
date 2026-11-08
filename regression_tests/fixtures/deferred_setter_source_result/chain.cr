lib LibC
  fun putchar(value : Int32) : Int32
end
class Reader
  def run(value : Int32)
    self.pos = value
  end
  def pos=(value)
    value
  end
end
def chain0
  chain1
end
def chain1
  chain2
end
def chain2
  chain3
end
def chain3
  chain4
end
def chain4
  chain5
end
def chain5
  chain6
end
def chain6
  chain7
end
def chain7
  chain8
end
def chain8
  chain9
end
def chain9
  Reader.new.run(65)
end
LibC.putchar(chain0)
LibC.putchar(10)
