# A' BEHAVIOR negative guard: a USER wrapper that escapes the Array buffer pointer
# must keep the element type INELIGIBLE for inline storage.
#
# The to_unsafe escape rule excludes only COMPILER-SYNTHESIZED abstract dispatchers
# (Object#/Reference#to_unsafe — RTA plumbing). It must STILL fail-close on a genuine
# user wrapper that forwards `@a.to_unsafe` and hands the raw @buffer pointer to
# opaque code: if WV were inline-stored, that escaped pointer would read the buffer
# at the legacy (boxed-ptr) stride → repr-mismatch / UAF. So WV must stay ineligible.
struct WV
  getter a : Int32
  getter b : Int32
  getter c : Int32

  def initialize(@a : Int32, @b : Int32, @c : Int32)
  end
end

# User wrapper (NOT a synthesized dispatcher): escapes the raw buffer pointer.
class Box
  def initialize(@a : Array(WV))
  end

  def leak : Pointer(WV)
    @a.to_unsafe
  end
end

arr = [] of WV
i = 0
while i < 6
  arr << WV.new(i, i, i)
  i += 1
end
arr.delete_at(1)
box = Box.new(arr)
p = box.leak
STDERR.puts "n=#{arr.size} ok=#{p.address != 0}"
STDOUT.flush
exit(0)
