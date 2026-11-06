class RequiredArgumentBlockMethod
  def self.run(value : Int32, &block : -> Int32)
    value + (yield)
  end
end

RequiredArgumentBlockMethod.run { 65 }
