# Regression test: unqualified (bare) sibling enum member names inside an enum's
# own instance methods must resolve to the member value, not degrade to null/zero.
# Bug: `case self when A` / `self == A` (bare `A`, no `TK::` prefix) fell through
# the constant path to a null literal, so `self` never matched -> wrong branch.
# In self-hosted stage2 this made TypeKind#primitive? (`case self when Void,
# Bool, ...`) misclassify Struct as primitive, so StaticArray / LibC::Stat type
# definitions were skipped and their `alloca %StaticArray...` uses were undefined
# -> llc reject. Qualified `TK::A` and `case` on a local always worked.
# EXPECT: enum_bare_sibling_ok

enum TK
  V0; V1; V2; V3; V4; V5
  V6; V7; V8; V9; V10; V11
  V12; V13; V14; V15; V16; V17; V18
  def prim?
    case self
    when V0, V1, V2, V3, V4, V5, V6, V7, V8, V9, V10, V11, V12, V13, V14, V15
      true
    else
      false
    end
  end

  def is_v5_bare?
    self == V5
  end
end

ok = true
ok = false unless TK::V5.prim? == true    # bare member in list -> matches
ok = false unless TK::V15.prim? == true   # boundary in list -> matches
ok = false unless TK::V16.prim? == false  # boundary out of list -> no match
ok = false unless TK::V18.prim? == false  # out of list -> no match
ok = false unless TK::V5.is_v5_bare? == true    # bare `self == V5` matches
ok = false unless TK::V6.is_v5_bare? == false   # bare `self == V5` non-match

if ok
  puts "enum_bare_sibling_ok"
else
  puts "FAIL"
end
