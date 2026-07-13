module RepeatedClassMethod
  def self.record(path : String) : Nil
  end
end

RepeatedClassMethod.record(__FILE__)
RepeatedClassMethod.record(__FILE__)
