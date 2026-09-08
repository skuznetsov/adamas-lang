@[Link("c")]
lib LibC
  fun exit(status : Int32) : Nil
end

class IO
  class FileDescriptor
  end
end

class File < IO::FileDescriptor
end

class File < IO::FileDescriptor
  def self.info?(value : Int32) : Info?
    return nil if value < 0
    File::Info.new
  end
end

module Crystal
  module DWARF
    struct Info
      def marker : Int32
        22
      end
    end
  end
end

class File
  struct Info
    def marker : Int32
      11
    end
  end
end

LibC.exit(3) unless File.info?(-1).nil?
value = File.info?(0)
status = if value
  value.marker == 11 ? 0 : 1
else
  2
end
LibC.exit(status)
