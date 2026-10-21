enum CharacterCode
  LetterA = 65
end
lib C
  fun putchar(value : CharacterCode) : Int32
end
enum OtherCode
  LetterA = 65
end
C.putchar(OtherCode::LetterA)
