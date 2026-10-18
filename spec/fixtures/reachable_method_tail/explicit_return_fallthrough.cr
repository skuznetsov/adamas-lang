module ReturnSummaryModuleProbe
  def self.final_return
    return 17
  end

  def self.branch_only(flag : Bool)
    if flag
      return 1
    else
      return 2
    end
  end

  def self.mixed_nil(flag : Bool)
    if flag
      return 9
    end
    nil
  end

  def self.mixed_string(flag : Bool)
    if flag
      return 9
    end
    "tail"
  end

  def self.mixed_int(flag : Bool)
    if flag
      return "head"
    end
    23
  end
end

class ReturnSummaryClassProbe
  def self.final_return
    return 17
  end

  def self.branch_only(flag : Bool)
    if flag
      return 1
    else
      return 2
    end
  end

  def self.mixed_nil(flag : Bool)
    if flag
      return 9
    end
    nil
  end

  def self.mixed_string(flag : Bool)
    if flag
      return 9
    end
    "tail"
  end

  def self.mixed_int(flag : Bool)
    if flag
      return "head"
    end
    23
  end
end

puts ReturnSummaryModuleProbe.final_return == 17
puts ReturnSummaryModuleProbe.branch_only(true) == 1
puts ReturnSummaryModuleProbe.branch_only(false) == 2
puts ReturnSummaryModuleProbe.mixed_nil(true) == 9
puts ReturnSummaryModuleProbe.mixed_nil(false).nil?
puts ReturnSummaryModuleProbe.mixed_string(true) == 9
puts ReturnSummaryModuleProbe.mixed_string(false) == "tail"
puts ReturnSummaryModuleProbe.mixed_int(true) == "head"
puts ReturnSummaryModuleProbe.mixed_int(false) == 23

puts ReturnSummaryClassProbe.final_return == 17
puts ReturnSummaryClassProbe.branch_only(true) == 1
puts ReturnSummaryClassProbe.branch_only(false) == 2
puts ReturnSummaryClassProbe.mixed_nil(true) == 9
puts ReturnSummaryClassProbe.mixed_nil(false).nil?
puts ReturnSummaryClassProbe.mixed_string(true) == 9
puts ReturnSummaryClassProbe.mixed_string(false) == "tail"
puts ReturnSummaryClassProbe.mixed_int(true) == "head"
puts ReturnSummaryClassProbe.mixed_int(false) == 23
