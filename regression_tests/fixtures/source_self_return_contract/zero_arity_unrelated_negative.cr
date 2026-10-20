class ZeroArityBase
  def self.make : self
    ZeroArityOther.new
  end
end
class ZeroArityChild < ZeroArityBase
end
class ZeroArityOther
end
ZeroArityChild.make
