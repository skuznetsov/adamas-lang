lib LibC
  fun exit(status : Int32) : NoReturn
end

class ParentStream
  class Error
    def self.code
      5
    end
  end
end

module Hidden
  private class Error
    def self.code
      7
    end
  end
end

class ChildStream < ParentStream
  include Hidden
end

LibC.exit(12) unless ::ChildStream::Error.code() == 5
LibC.exit(0)
