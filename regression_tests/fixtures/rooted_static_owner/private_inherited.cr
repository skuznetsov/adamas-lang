class ParentStream
  private class Error
    def self.code
      5
    end
  end
end

class ChildStream < ParentStream
end

::ChildStream::Error.code()
