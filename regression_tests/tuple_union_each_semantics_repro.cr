require "lib_c"
require "macros"
require "object"
require "crystal/once"
require "comparable"
require "exception"
require "iterable"
require "iterator"
require "steppable"
require "indexable"
require "string"
require "number"
require "primitives"
require "char"
require "enum"
require "enumerable"
require "errno"
require "winerror"
require "wasi_error"
require "tuple"
require "path"

lib LibC
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

def mark(label : Int32, ok : Bool)
  LibC.putchar(label)
  LibC.putchar(61)
  LibC.putchar(ok ? 49 : 48)
  LibC.putchar(10)
end

def each_count(kind : Path::Kind) : Int32
  count = 0
  Path.separators(kind).each do |_separator|
    count += 1
  end
  count
end

def each_sum(kind : Path::Kind) : Int32
  sum = 0
  Path.separators(kind).each do |separator|
    sum += separator.ord
  end
  sum
end

def each_returns_nil(kind : Path::Kind) : Bool
  result = Path.separators(kind).each { |_separator| }
  result.nil?
end

def any_early_return(kind : Path::Kind) : Int32
  Path.separators(kind).any? do |separator|
    return 1 if separator == '\\'
    false
  end
  0
end

def all_early_return(kind : Path::Kind) : Int32
  Path.separators(kind).all? do |separator|
    return 1 if separator == '\\'
    true
  end
  2
end

def next_count(kind : Path::Kind) : Int32
  count = 0
  Path.separators(kind).each do |separator|
    next if separator == '\\'
    count += 1
  end
  count
end

def break_count(kind : Path::Kind) : Int32
  count = 0
  Path.separators(kind).each do |separator|
    count += 1
    break if separator == '/'
  end
  count
end

def break_value(kind : Path::Kind) : Int32
  result = Path.separators(kind).each do |separator|
    break 73 if separator == '/'
  end
  result || -1
end

def heterogeneous_count : Int32
  count = 0
  { '/', 7 }.each do |_value|
    count += 1
  end
  count
end

def empty_count : Int32
  count = 0
  Tuple.new.each do |_value|
    count += 1
  end
  count
end

posix = Path::Kind::POSIX
windows = Path::Kind::WINDOWS

mark(80, each_count(posix) == 1)
mark(87, each_count(windows) == 2)
mark(112, each_sum(posix) == 47)
mark(119, each_sum(windows) == 139)
mark(82, each_returns_nil(posix) && each_returns_nil(windows))
mark(65, any_early_return(posix) == 0 && any_early_return(windows) == 1)
mark(76, all_early_return(posix) == 2 && all_early_return(windows) == 1)
mark(78, next_count(posix) == 1 && next_count(windows) == 1)
mark(66, break_count(posix) == 1 && break_count(windows) == 2)
mark(86, break_value(posix) == 73 && break_value(windows) == 73)
mark(72, heterogeneous_count == 2)
mark(69, empty_count == 0)

LibC.exit(0)
