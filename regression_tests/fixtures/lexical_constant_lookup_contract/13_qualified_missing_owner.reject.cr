module QualifiedMissingOwner
  def self.read : Int32
    AbsentNested::VALUE
  end
end

QualifiedMissingOwner.read
