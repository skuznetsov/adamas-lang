lib LibC
  fun exit(code : Int32) : NoReturn
end

class Socket
  class Error
    def self.make
      new
    end

    def code : Int32
      17
    end
  end
end

module Crystal::System::Socket
  private def system_listen(flag)
    ::Socket::Error.make unless flag
  end
end

class Socket
  include Crystal::System::Socket

  def listen(flag : Bool)
    system_listen(flag)
  end
end

class Server < Socket
end

def root_code(error : ::Socket::Error) : Int32
  error.code
end

def flag : Bool
  false
end

if error = Server.new.listen(flag)
  LibC.exit(1) unless root_code(error) == 17
else
  LibC.exit(2)
end
LibC.exit(0)
