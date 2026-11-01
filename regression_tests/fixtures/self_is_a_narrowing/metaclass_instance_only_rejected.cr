class MetaNegativeBase
  def self.guarded : Bool
    self.is_a?(MetaNegativeChild.class) && self.instance_only
  end
end

class MetaNegativeChild < MetaNegativeBase
  def instance_only : Bool
    true
  end
end

MetaNegativeChild.guarded
