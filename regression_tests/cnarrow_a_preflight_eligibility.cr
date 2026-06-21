# C-narrow-a PREFLIGHT eligibility reducer (gate ADAMAS_CNARROW_A_PREFLIGHT).
#
# The read-only preflight classifies every struct ctor pushed into a container by
# the C-narrow-a gate (GPT review round 1):
#   inline_array_storage_eligible(T) && semantic_recursive_pod(T) &&
#   fresh sole-use ctor && monomorphic Array(T)#push
# with reason codes eligible / not_pod / not_storage_eligible / not_sole_use /
# erased_push. This .cr instantiates one shape per decision-relevant reason so the
# companion .sh can assert the classifier discriminates them.
#
#   Vec3  (leaf POD, sole-use push)     -> eligible
#   Vec3  (ctor result used twice)      -> not_sole_use
#   Pair{Vec2,Vec2} (nested POD)        -> not_storage_eligible  (Blocker-2 case:
#       semantic-POD TRUE but current Array storage NOT inline — struct fields are
#       pointer carriers today, so leaf_storage_pod_struct? rejects it)
#   Box{String} (ref-owning)            -> NOT eligible (this compiler promotes a
#       ref-field struct to a CLASS, so its ctor is not a struct ctor -> excluded;
#       a SAFE fail-closed exclusion. The not_pod reason is instead exercised by
#       prelude struct-kind-but-non-POD types, e.g. DWARF FileEntry.)
struct Vec2
  getter a : Int32
  getter b : Int32

  def initialize(@a : Int32, @b : Int32)
  end
end

struct Vec3
  getter a : Int32
  getter b : Int32
  getter c : Int32

  def initialize(@a : Int32, @b : Int32, @c : Int32)
  end
end

struct Pair
  getter x : Vec2
  getter y : Vec2

  def initialize(@x : Vec2, @y : Vec2)
  end
end

struct Box
  getter s : String

  def initialize(@s : String)
  end
end

# --- Vec3: ELIGIBLE (sole-use pushes + full bulk exercise -> storage-eligible) ---
arr = [] of Vec3
i = 0
while i < 12
  arr << Vec3.new(i, i * 2, i * 3) # sole-use ctor push -> eligible
  i += 1
end
arr.delete_at(2)
other = [] of Vec3
other << Vec3.new(7, 7, 7) # sole-use push -> eligible
arr.shift
arr.concat(other)
sum = 0
k = 0
while k < arr.size
  v = arr[k]
  sum += v.a + v.b + v.c
  k += 1
end

# --- Vec3: NOT_SOLE_USE (ctor result used by the push AND a field read) ---
# arr2 must stay LIVE (read an element below) or DCE drops the push and the site
# is no longer "container-pushed" -> would not be classified at all.
arr2 = [] of Vec3
w = Vec3.new(100, 200, 300)
arr2 << w
extra = w.a + arr2[0].b # w used twice (<< and .a) -> not_sole_use; arr2 read -> live

# --- Pair: NOT_STORAGE_ELIGIBLE (semantic-POD, but nested struct fields) ---
pairs = [] of Pair
pairs << Pair.new(Vec2.new(1, 2), Vec2.new(3, 4))
plen = pairs[0].x.a # keep pairs live

# --- Box: NOT_POD (String field, ref-owning) ---
boxes = [] of Box
boxes << Box.new("hi")
blen = boxes[0].s.size # keep boxes live

STDERR.puts "sum=#{sum} extra=#{extra} pairs=#{pairs.size} plen=#{plen} boxes=#{boxes.size} blen=#{blen}"
STDERR.flush
exit(0)
