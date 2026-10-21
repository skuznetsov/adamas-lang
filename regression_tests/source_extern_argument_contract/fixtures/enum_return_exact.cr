enum CharacterCode
  LetterA = 65
end
lib C
  fun putchar(value : CharacterCode) : Int32
end
def enum_value : CharacterCode
  CharacterCode::LetterA
end
C.putchar(enum_value)
