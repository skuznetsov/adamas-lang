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
  LessEq
  GreaterEq
  Spaceship
  EqEq
  EqEqEq
  NotEq
  Match
  NotMatch
  In
  Pipe
  Caret
  Amp
  LShift
  RShift
  Plus
  Minus
  AmpPlus
  AmpMinus
  Star
  Slash
  FloorDiv
  Percent
  AmpStar
  StarStar
  AmpStarStar
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
  Kind::LessEq      => 6,
  Kind::GreaterEq   => 6,
  Kind::Spaceship   => 6,
  Kind::EqEq        => 7,
  Kind::EqEqEq      => 7,
  Kind::NotEq       => 7,
  Kind::Match       => 7,
  Kind::NotMatch    => 7,
  Kind::In          => 7,
  Kind::Pipe        => 8,
  Kind::Caret       => 8,
  Kind::Amp         => 9,
  Kind::LShift      => 10,
  Kind::RShift      => 10,
  Kind::Plus        => 11,
  Kind::Minus       => 11,
  Kind::AmpPlus     => 11,
  Kind::AmpMinus    => 11,
  Kind::Star        => 20,
  Kind::Slash       => 20,
  Kind::FloorDiv    => 20,
  Kind::Percent     => 20,
  Kind::AmpStar     => 20,
  Kind::StarStar    => 25,
  Kind::AmpStarStar => 25,
}

value = BINARY_PRECEDENCE[Kind::Rescue]? || 0
LibC.exit(value == 1 ? 0 : 1)
