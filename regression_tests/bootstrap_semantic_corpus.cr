# No-prelude semantic corpus for bootstrap-stage HIR/MIR/LLVM comparisons.
#
# Keep this intentionally small and dependency-light. The purpose is not runtime
# coverage; it is a stable frontend/lowering shape that every bootstrap stage can
# compile with `--no-prelude --no-link --emit ...`.

def add(a : Int32, b : Int32)
  a + b
end

def choose(flag : Bool)
  if flag
    1
  else
    2
  end
end

def reducer(&)
  yield
end

def mixed(p : Int32 -> Nil, &)
  yield
end

value = add(1, 2)
choose(value == 3)

reducer do
end

mixed(->(x : Int32) { }, &->{})
