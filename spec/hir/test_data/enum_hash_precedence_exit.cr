@[Extern]
lib LibC
  fun exit(status : Int32) : NoReturn
end

enum Kind
  Rescue
  Question
  NilCoalesce
  OrOr
  AndAnd
  DotDot
  DotDotDot
  Less
  Greater
end

BINARY_PRECEDENCE = {
  Kind::Rescue      => 1,
  Kind::Question    => 2,
  Kind::NilCoalesce => 3,
  Kind::OrOr        => 3,
  Kind::AndAnd      => 4,
  Kind::DotDot      => 5,
  Kind::DotDotDot   => 5,
  Kind::Less        => 6,
  Kind::Greater     => 6,
}

value = BINARY_PRECEDENCE[Kind::Rescue]? || 0
LibC.exit(value == 1 ? 0 : 1)
