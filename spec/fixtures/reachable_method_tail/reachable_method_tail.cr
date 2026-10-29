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

  def return_only_while(flag : Bool)
    while true
      return 42_u32 if flag
    end
  end

  def return_only_until(flag : Bool)
    until false
      return 42_u32 if flag
    end
  end

  def while_break_value
    while true
      break 42
    end
  end

  def until_break_value
    until false
      break 42
    end
  end

  def while_normal_exit(flag : Bool)
    while flag
      break 42
    end
  end

  def until_normal_exit(flag : Bool)
    until flag
      break 42
    end
  end

  def while_mixed_break(flag : Bool)
    while true
      break 42 if flag
      break "tail"
    end
  end

  def until_bare_break(flag : Bool)
    until false
      break 42 if flag
      break
    end
  end

  def endless_while
    while true
    end
  end

  def endless_until
    until false
    end
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

  def return_only_while(flag : Bool)
    while true
      return 42_u32 if flag
    end
  end

  def return_only_until(flag : Bool)
    until false
      return 42_u32 if flag
    end
  end

  def while_break_value
    while true
      break 42
    end
  end

  def until_break_value
    until false
      break 42
    end
  end

  def while_normal_exit(flag : Bool)
    while flag
      break 42
    end
  end

  def until_normal_exit(flag : Bool)
    until flag
      break 42
    end
  end

  def while_mixed_break(flag : Bool)
    while true
      break 42 if flag
      break "tail"
    end
  end

  def until_bare_break(flag : Bool)
    until false
      break 42 if flag
      break
    end
  end

  def endless_while
    while true
    end
  end

  def endless_until
    until false
    end
  end
end
