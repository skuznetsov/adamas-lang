# A' mini-AbiFacts reducer: Array bulk-op coverage facts (read-only).
#
# Two 12-byte leaf-POD structs (stride != pointer) exercise the two poles of the
# fail-closed eligibility bit `Type#inline_array_storage_eligible`:
#
#   Cov — used ONLY through bulk ops whose @buffer provenance + element stride are
#         structurally provable: push/<<, [], delete_at, shift, insert, concat
#         (same-element Array(Cov)). Every bulk op classifies MoveCopySameElem /
#         Clear / AllocRealloc -> ELIGIBLE.
#
#   Unc — additionally used through dup/reverse, which copy into a FRESH, non-self
#         Array(Unc) buffer (a local, not the self/arg @buffer the analysis can
#         prove). Those copies stay Uncovered -> the whole type fail-closes to
#         ineligible. This proves the to_unsafe/fresh-malloc provenance refinement
#         did NOT open a hole: an unprovable copy still excludes the type.
struct Cov
  getter x : Int32
  getter y : Int32
  getter z : Int32

  def initialize(@x : Int32, @y : Int32, @z : Int32)
  end
end

struct Unc
  getter a : Int32
  getter b : Int32
  getter c : Int32

  def initialize(@a : Int32, @b : Int32, @c : Int32)
  end
end

cov = [] of Cov
i = 0
while i < 6
  cov << Cov.new(i, i + 1, i + 2)
  i += 1
end
cov.delete_at(2)
cov.insert(1, Cov.new(9, 9, 9))
cov.shift
cov2 = [] of Cov
cov2 << Cov.new(1, 2, 3)
cov.concat(cov2)
cfirst = cov[0]

unc = [] of Unc
j = 0
while j < 5
  unc << Unc.new(j, j + 1, j + 2)
  j += 1
end
ud = unc.dup
ur = unc.reverse
ufirst = unc[0]

STDERR.puts "cov=#{cov.size} cf=#{cfirst.x} ud=#{ud.size} ur=#{ur.size} uf=#{ufirst.a}"
STDOUT.flush
exit(0)
