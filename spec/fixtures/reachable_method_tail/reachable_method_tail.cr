module ReachableTailModule
  extend self

  def explicit_terminal
    return 41
  end

  def all_branches_terminal(flag : Bool)
    if flag
      return 1
    else
      return 2
    end
  end

  def nil_tail_after_return(flag : Bool)
    if flag
      return 1
    end
    nil
  end

  def string_tail_after_return(flag : Bool)
    if flag
      return 1
    end
    "tail"
  end
end

class ReachableTailClass
  def explicit_terminal
    return 41
  end

  def all_branches_terminal(flag : Bool)
    if flag
      return 1
    else
      return 2
    end
  end

  def nil_tail_after_return(flag : Bool)
    if flag
      return 1
    end
    nil
  end

  def string_tail_after_return(flag : Bool)
    if flag
      return 1
    end
    "tail"
  end
end
