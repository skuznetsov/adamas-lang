lib LibC
  fun puts(text : UInt8*) : Int32
  fun strlen(text : UInt8*) : UInt64
end

class String
  def to_unsafe : UInt8*
    pointerof(@c)
  end
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

  def evaluate_text(depth : Int32) : String
    return "Z" if depth < 0
    flag(depth) ? "A" : "C"
  end

  def flag(depth : Int32) : Bool
    request(depth)
  end

  def request(depth : Int32) : Bool
    LibC.strlen(evaluate_text(depth &- 1)) == 1_u64
  end
end

evaluator = Evaluator.new
LibC.puts(evaluator.entry0(0))
LibC.puts(evaluator.entry0(-1))
