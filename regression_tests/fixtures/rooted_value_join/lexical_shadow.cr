lib LibC
  fun exit(code : Int32) : NoReturn
end

class EndpointError
  def code : Int32
    17
  end
end

module Platform
  class EndpointError
    def code : Int32
      39
    end
  end

  def self.root_error(flag : Bool)
    ::EndpointError.new unless flag
  end

  def self.local_error(flag : Bool)
    EndpointError.new unless flag
  end
end

def root_code(error : ::EndpointError) : Int32
  error.code
end

def local_code(error : ::Platform::EndpointError) : Int32
  error.code
end

def flag : Bool
  false
end

if error = Platform.root_error(flag)
  LibC.exit(1) unless root_code(error) == 17
else
  LibC.exit(2)
end
if error = Platform.local_error(flag)
  LibC.exit(3) unless local_code(error) == 39
else
  LibC.exit(4)
end
LibC.exit(5) if Platform.root_error(true)
LibC.exit(6) if Platform.local_error(true)
LibC.exit(0)
