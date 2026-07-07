# L10-β regression: loop-header/exit phis must cover EVERY real predecessor.
# Two historical roots (2026-07-07, session-12):
#  1. lower_while/lower_loop skipped the self-referential backedge incoming for
#     variables unchanged on the backedge path -> backend fabricated null/zero
#     for the missing edge.
#  2. lower_block_to_block_id lowered the detached block body with the caller's
#     loop stacks active -> `next`/`break` inside a block passed to a
#     proc-materialized yield method wired dead edges into the ENCLOSING while
#     (extra phi predecessors with fabricated null incomings; in-vivo this was
#     lower_super's `each_param do |param| next if ... break ... end`).
# EXPECT: loop_phi_backedge_ok

class Name
  def initialize(@v : Int32)
  end

  def v : Int32
    @v
  end
end

def make_name(v : Int32) : Name
  Name.new(v)
end

def lookup(p : Int32) : Name?
  p == 3 ? make_name(111) : nil
end

def seen_add(p : Int32) : Bool
  p < 100
end

def advance(p : Int32) : Int32?
  p >= 5 ? nil : p + 1
end

def advance2(p : Int32) : Int32?
  nil
end

def each_k(n : Int32)
  j = 0
  while j < n
    yield j
    j += 1
  end
end

def run(start : Int32) : Int32
  x : Name? = nil
  probe : Int32? = start
  while probe
    p = probe.not_nil!
    break unless seen_add(p)
    if cand = lookup(p)
      ok = true
      acc = 0
      each_k(3) do |k|
        next if k == 1
        if k == 2 && p == 999
          ok = false
          break
        end
        acc += k
      end
      if ok && p != 999
        x = cand
        break
      end
    end
    probe = advance(p) || advance2(p)
  end
  unless x
    x = make_name(777)
  end
  resolved = x.not_nil!
  resolved.v
end

# Case A: walks 1,2,3 -> lookup(3) hits -> 111
a = run(1)
# Case B: walks 4,5 -> advance(5)=nil, advance2=nil -> loop exhausts -> fallback 777
b = run(4)
puts "A=#{a} B=#{b}"
if a == 111 && b == 777
  puts "loop_phi_backedge_ok"
else
  puts "loop_phi_backedge_MISMATCH a=#{a} b=#{b}"
end
