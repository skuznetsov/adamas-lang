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
  def entry0(depth : Int32) : String
    entry1(depth)
  end

  def entry1(depth : Int32) : String
    entry2(depth)
  end

  def entry2(depth : Int32) : String
    evaluate_expression(depth)
  end

  def evaluate_expression(depth : Int32) : String
    return "Z" if depth < 0
    return evaluate_to_macro_value(depth &- 1) if depth == 3
    callback = -> {
      LibC.puts("callback")
      evaluate_to_macro_value(depth &- 1) # proc result
    }
    if result = assign_macro_target(depth) { callback.call }
      result
    else
      "N"
    end
  end

  def assign_macro_target(depth : Int32, & : -> String) : String?
    return nil if depth == 2
    return yield if depth == 1
    apply_macro_index_assignment(depth) { yield }
  end

  def apply_macro_index_assignment(depth : Int32, & : -> String) : String?
    flag = request_flag(depth)
    return yield if flag
    return nil if depth < 0
    yield
  end

  def evaluate_to_macro_value(depth : Int32) : String
    return "A" if depth < 0
    return "P" if request_flag(depth)
    "Q" # producer result
  end

  def request_flag(depth : Int32) : Bool
    delegate_flag(depth)
  end

  def delegate_flag(depth : Int32) : Bool
    LibC.strlen(evaluate_expression(depth &- 1)) == 1_u64
  end
end

evaluator = Evaluator.new
LibC.puts(evaluator.entry0(0))
LibC.puts(evaluator.entry0(1))
LibC.puts(evaluator.entry0(2))
LibC.puts(evaluator.entry0(3))
