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
 def initialize(message : Int32, *, @file : Int32, @other : Int32? = nil)
  super message, target: @file
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
error = MissingFileError.new(65, file: 66)
Native.putchar(error.value)
Native.putchar(error.file)
Native.putchar(10)
