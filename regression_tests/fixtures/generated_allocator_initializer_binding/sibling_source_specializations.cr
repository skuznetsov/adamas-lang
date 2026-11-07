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
first = FileError.new(65, file: 66)
second = MissingFileError.new(67, file: 68)
Native.putchar(first.value)
Native.putchar(first.file)
Native.putchar(second.value)
Native.putchar(second.file)
Native.putchar(10)
