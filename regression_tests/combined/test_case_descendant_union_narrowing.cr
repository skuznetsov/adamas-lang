# Regression: a nullable base-class union must preserve descendant case narrowing.
# EXPECT: case_descendant_union_narrowing_ok

struct CaseExprId
  getter index : Int32

  def initialize(@index : Int32)
  end
end

abstract class CaseNodeBase
end

class CaseAssignNode < CaseNodeBase
  getter value : CaseExprId

  def initialize(@value : CaseExprId)
  end
end

class CaseOtherNode < CaseNodeBase
end

class CaseProbe
  def inspect_node(node : CaseNodeBase?) : Int32
    case node
    when CaseAssignNode
      node.value.index
    else
      -1
    end
  end

  def classify(node : CaseNodeBase?) : Int32
    case node
    when CaseAssignNode, CaseOtherNode
      1
    else
      0
    end
  end
end

probe = CaseProbe.new
assign_value = probe.inspect_node(CaseAssignNode.new(CaseExprId.new(37)))
other_value = probe.inspect_node(CaseOtherNode.new)
assign_class = probe.classify(CaseAssignNode.new(CaseExprId.new(1)))
other_class = probe.classify(CaseOtherNode.new)
nil_class = probe.classify(nil)

if assign_value == 37 && other_value == -1 &&
   assign_class == 1 && other_class == 1 && nil_class == 0
  puts "case_descendant_union_narrowing_ok"
else
  puts "case_descendant_union_narrowing_failed"
end
