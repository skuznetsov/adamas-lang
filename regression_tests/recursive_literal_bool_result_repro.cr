lib LibC
  fun putchar(c : Int32) : Int32
end

class Evaluator
  def entry0(depth)
    entry1(depth)
  end

  def entry1(depth)
    entry2(depth)
  end

  def entry2(depth)
    evaluate_text(depth)
  end

  def evaluate_text(depth : Int32) : Int32
    flag(depth) ? 65 : 90
  end

  def flag(depth : Int32) : Bool
    return false if depth < 0
    request(depth)
  end

  def request(depth : Int32) : Bool
    return true if depth == 0
    evaluate_text(depth &- 1) == 65
  end
end

evaluator = Evaluator.new
LibC.putchar(evaluator.entry0(3))
LibC.putchar(evaluator.entry0(-1))
LibC.putchar(10)
