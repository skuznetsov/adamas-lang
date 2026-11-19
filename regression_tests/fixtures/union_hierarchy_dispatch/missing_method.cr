abstract class MissingMethodRoot
  abstract def code : Int32
end

class MissingMethodChild < MissingMethodRoot
  def code : Int32
    65
  end
end

class MissingMethodOther
end

def rejected(value : MissingMethodRoot | MissingMethodOther)
  value.code
end

rejected(MissingMethodOther.new)
