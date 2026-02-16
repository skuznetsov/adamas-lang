# Test simple recursive sum
def sum(n : Int32) : Int32
  if n <= 0
    0
  else
    n + sum(n - 1)
  end
end

def main : Int32
  sum(5)
end
