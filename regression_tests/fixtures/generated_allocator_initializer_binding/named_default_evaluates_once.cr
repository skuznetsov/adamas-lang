lib Native
 fun putchar(value : Int32) : Int32
end
class BaseError
 def initialize(@value : Int32 = 65, *, target : Int32? = nil)
 end
 def value
  @value
 end
end
class FileError < BaseError
 def initialize(message : Int32, *, @file : Int32, @other : Int32 = FileError.mark(67))
  super message, target: @file
 end
 def self.mark(value : Int32)
  Native.putchar(value)
  value
 end
 def other
  @other
 end
 def file
  @file
 end
 def self.create(message, **opts)
  self.new_from_code(message, **opts)
 end
 private def self.new_from_code(message, **opts)
  MissingFileError.new(message, **opts)
 end
end
class MissingFileError < FileError
end
error = MissingFileError.new(FileError.mark(65), file: FileError.mark(66))
Native.putchar(error.value)
Native.putchar(error.file)
Native.putchar(error.other)
Native.putchar(10)
