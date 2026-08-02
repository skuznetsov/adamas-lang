class Object
  def ===(other) : Bool
    self == other
  end

  def ==(other) : Bool
    false
  end
end

enum CaseKind
  First
  Second
end

def exact_kind : CaseKind
  CaseKind::First
end

def nilable_kind : CaseKind?
  nil
end

def compare_exact : Bool
  case exact_kind
  when CaseKind::First
    true
  else
    false
  end
end

def compare_nilable : Bool
  case nilable_kind
  when CaseKind::First
    true
  else
    false
  end
end

compare_exact
compare_nilable
