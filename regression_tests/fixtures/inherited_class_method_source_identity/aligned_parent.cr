class AlignedSourceParent
  def self.build(parent value : Int32) : self
    new(value)
  end

  def initialize(@value : Int32)
  end

  def code : Int32
    66
  end
end
