# Combined: Structs, enums, records
# EXPECT: structs_enums_all_ok

# --- Struct basics ---
struct Point
  getter x : Float64
  getter y : Float64

  def initialize(@x : Float64, @y : Float64)
  end

  def distance_to(other : Point) : Float64
    dx = @x - other.x
    dy = @y - other.y
    Math.sqrt(dx * dx + dy * dy)
  end

  def +(other : Point) : Point
    Point.new(@x + other.x, @y + other.y)
  end

  def to_s : String
    "(#{@x}, #{@y})"
  end
end

p1 = Point.new(0.0, 0.0)
p2 = Point.new(3.0, 4.0)
puts p1.to_s
puts p2.to_s
puts p1.distance_to(p2)
puts (p1 + p2).to_s

# --- Struct with default values ---
struct Color
  getter r : UInt8
  getter g : UInt8
  getter b : UInt8

  def initialize(@r : UInt8 = 0_u8, @g : UInt8 = 0_u8, @b : UInt8 = 0_u8)
  end

  def to_s : String
    "rgb(#{@r},#{@g},#{@b})"
  end
end

black = Color.new
white = Color.new(255_u8, 255_u8, 255_u8)
red = Color.new(r: 255_u8)
puts black.to_s
puts white.to_s
puts red.to_s

# --- Enum basics ---
enum Direction
  North
  South
  East
  West
end

d = Direction::North
puts d
puts d.value

# --- Enum with case ---
def move(dir : Direction) : String
  case dir
  when Direction::North then "up"
  when Direction::South then "down"
  when Direction::East  then "right"
  when Direction::West  then "left"
  else "unknown"
  end
end

puts move(Direction::North)
puts move(Direction::East)

# --- Enum with values ---
enum Priority
  Low    = 1
  Medium = 5
  High   = 10
end

puts Priority::Low.value
puts Priority::High.value

# --- Enum flags ---
@[Flags]
enum Permissions
  Read
  Write
  Execute
end

perms = Permissions::Read | Permissions::Write
puts perms.includes?(Permissions::Read)
puts perms.includes?(Permissions::Execute)

# --- Struct in array ---
points = [Point.new(1.0, 1.0), Point.new(2.0, 2.0), Point.new(3.0, 3.0)]
points.each { |p| puts p.to_s }
puts points.size

# --- Record-like struct ---
struct Token
  getter kind : String
  getter value : String
  getter line : Int32

  def initialize(@kind : String, @value : String, @line : Int32)
  end

  def to_s : String
    "#{@kind}:#{@value}@#{@line}"
  end
end

tokens = [
  Token.new("ident", "foo", 1),
  Token.new("op", "+", 1),
  Token.new("int", "42", 1),
]
tokens.each { |t| puts t.to_s }

puts "structs_enums_all_ok"
