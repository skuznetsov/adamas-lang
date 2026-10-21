enum CharacterCode
  LetterA = 65
end
lib C
  fun putchar(value : CharacterCode) : Int32
end
value = CharacterCode::LetterA
C.putchar(value)
