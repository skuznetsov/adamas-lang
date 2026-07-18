# Reducer for the union-static generic materialization boundary.
#
# Concrete insertion and union insertion are both legal, distinct
# specializations.  The invariant is that each selected `<<`/`push` target
# keeps its receiver and value, has a matching body, and only receives a
# union-wrapped value when the source expression is actually union-typed.

class AstArena
end

class PageArena
end

class VirtualArena
end

alias ArenaLike = AstArena | PageArena | VirtualArena

class Array(T)
  def initialize
  end

  def push(value : T) : self
    self
  end

  def <<(value : T) : self
    push(value)
  end
end

# A concrete value may lawfully select the concrete generic specialization.
def append_static(values : Array(ArenaLike), arena : AstArena)
  values << arena
end

# An explicit cast is the authoritative request for a union specialization.
# A typed local assignment is deliberately insufficient as an oracle because
# upstream Crystal may retain the concrete flow type for that assignment.
def append_explicit(values : Array(ArenaLike), arena : AstArena)
  values << arena.as(ArenaLike)
end

# A true union parameter must remain union-shaped without re-wrapping inside
# the function body.
def append_union(values : Array(ArenaLike), arena : ArenaLike)
  values << arena
end

values = Array(ArenaLike).new
arena = AstArena.new
append_static(values, arena)
append_explicit(values, arena)
append_union(values, arena.as(ArenaLike))
1
