enum CharacterCode
  LetterA = 65
  Newline = 10
end
lib C
  fun putchar(value : CharacterCode) : Int32
end
C.putchar(CharacterCode::LetterA)
C.putchar(CharacterCode::Newline)
