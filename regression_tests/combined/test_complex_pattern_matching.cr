# Complex: Sophisticated case/when, type narrowing, union dispatch
# EXPECT: pattern_matching_all_ok

# --- Case with multiple values ---
def classify_char(c : Char) : String
  case c
  when 'a', 'e', 'i', 'o', 'u'
    "vowel"
  when '0'..'9'
    "digit"
  when ' ', '\t', '\n'
    "whitespace"
  else
    "consonant"
  end
end

puts classify_char('a')
puts classify_char('b')
puts classify_char('5')
puts classify_char(' ')

# --- Union type dispatch ---
alias JSON = String | Int32 | Float64 | Bool | Nil | Array(JSON)

def json_type(v : JSON) : String
  case v
  when String  then "string"
  when Int32   then "int"
  when Float64 then "float"
  when Bool    then "bool"
  when Nil     then "null"
  when Array   then "array"
  else              "unknown"
  end
end

puts json_type("hello")
puts json_type(42)
puts json_type(3.14)
puts json_type(true)
puts json_type(nil)

# --- Nested type narrowing ---
class Result
  getter value : String?
  getter error : String?

  def initialize(@value : String? = nil, @error : String? = nil)
  end

  def success? : Bool
    !@value.nil? && @error.nil?
  end
end

def process(r : Result) : String
  if r.success?
    if v = r.value
      "OK: #{v}"
    else
      "OK but nil value"
    end
  else
    if e = r.error
      "ERR: #{e}"
    else
      "ERR unknown"
    end
  end
end

puts process(Result.new(value: "data"))
puts process(Result.new(error: "failed"))
puts process(Result.new)

# --- Responsive dispatch (is_a? chains) ---
abstract class Expr
  abstract def eval : Int32
end

class Literal < Expr
  getter value : Int32

  def initialize(@value : Int32)
  end

  def eval : Int32
    @value
  end
end

class Add < Expr
  getter left : Expr
  getter right : Expr

  def initialize(@left : Expr, @right : Expr)
  end

  def eval : Int32
    @left.eval + @right.eval
  end
end

class Mul < Expr
  getter left : Expr
  getter right : Expr

  def initialize(@left : Expr, @right : Expr)
  end

  def eval : Int32
    @left.eval * @right.eval
  end
end

# (2 + 3) * (4 + 1) = 25
expr = Mul.new(
  Add.new(Literal.new(2), Literal.new(3)),
  Add.new(Literal.new(4), Literal.new(1))
)
puts expr.eval

# --- Dispatch through array of abstract ---
exprs = [] of Expr
exprs << Literal.new(10)
exprs << Add.new(Literal.new(1), Literal.new(2))
exprs << Mul.new(Literal.new(3), Literal.new(4))

exprs.each do |e|
  puts e.eval
end

puts "pattern_matching_all_ok"
