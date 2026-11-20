lib LibC
  fun putchar(c : Int32) : Int32
end

module RecursiveTupleResult
  abstract class MacroValue
    abstract def truthy? : Bool
  end

  class MacroBooleanValue < MacroValue
    def initialize(@value : Bool)
    end

    def truthy? : Bool
      @value
    end
  end

  class MacroNumberValue < MacroValue
    def value : Int64
      @value
    end

    def initialize(@value : Int64)
    end

    def truthy? : Bool
      @value != 0
    end
  end

  class MacroNilValue < MacroValue
    def truthy? : Bool
      false
    end
  end

  class Expr
  end

  class ExprId
    def node : Expr?
      @node
    end

    def initialize(@node : Expr?)
    end
  end

  class BooleanExpr < Expr
    def value : Bool
      @value
    end

    def initialize(@value : Bool)
    end
  end

  class NumberExpr < Expr
    def value : Int64
      @value
    end

    def initialize(@value : Int64)
    end
  end

  class IfExpr < Expr
    def condition : Expr
      @condition
    end
    def then_branch : Expr
      @then_branch
    end
    def else_branch : Expr
      @else_branch
    end

    def initialize(@condition : Expr, @then_branch : Expr, @else_branch : Expr)
    end
  end

  class TupleCycleProbe
    class Context
      def depth : Int32
        @depth
      end

      def initialize(@depth : Int32 = 0)
      end

      def with_depth(depth : Int32) : Context
        Context.new(depth)
      end
    end

    def entry0 : Bool
      entry1
    end

    def entry1 : Bool
      entry2
    end

    def entry2 : Bool
      run
    end

    def run : Bool
      expression = IfExpr.new(NumberExpr.new(1_i64), BooleanExpr.new(true), BooleanExpr.new(false))
      evaluate_to_macro_value(ExprId.new(expression), Context.new).truthy?
    end

    private def evaluate_to_macro_value(expr_id : ExprId, context : Context) : MacroValue
      expr = node_for_expr?(expr_id)
      return MacroNilValue.new unless expr

      if conditional = expr.as?(IfExpr)
        selected, next_context = evaluate_condition(ExprId.new(conditional.condition), context)
        branch = selected ? conditional.then_branch : conditional.else_branch
        evaluate_to_macro_value(ExprId.new(branch), next_context)
      elsif boolean = expr.as?(BooleanExpr)
        MacroBooleanValue.new(boolean.value)
      elsif number = expr.as?(NumberExpr)
        MacroNumberValue.new(number.value)
      else
        MacroNilValue.new
      end
    end

    private def evaluate_condition(expr_id : ExprId, context : Context) : {Bool, Context}
      expr = node_for_expr?(expr_id)
      return {false, context} unless expr

      if expr.is_a?(NumberExpr)
        number = macro_condition_number_value(expr_id, context)
        return {false, context} unless number
        {number != 0, context.with_depth(context.depth &+ 1)}
      else
        value = evaluate_to_macro_value(expr_id, context)
        {value.truthy?, context.with_depth(context.depth &+ 1)}
      end
    end

    private def macro_condition_number_value(expr_id : ExprId, context : Context) : Int64?
      expr = node_for_expr?(expr_id)
      return nil unless expr

      value = evaluate_to_macro_value(expr_id, context)
      number = value.as?(MacroNumberValue) || return nil
      number.value
    end

    private def node_for_expr?(expr_id : ExprId) : Expr?
      expr_id.node
    end
  end
end

result = RecursiveTupleResult::TupleCycleProbe.new.entry0
LibC.putchar(result ? 84 : 70)
LibC.putchar(10)
