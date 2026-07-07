# L12 regression (2026-07-07, session-14): Array(CustomStruct)#== was ALWAYS
# false, even `a == a`. Two layers:
# D1 (root): in Indexable#equals?(other : Indexable, &) the yield-arg
#   `other.unsafe_fetch(i)` inferred its type through the BARE generic param
#   annotation -> block param typed raw Pointer instead of the element struct
#   (the callsite mono `equals?$$Array(TRef)` knows the concrete type; it was
#   ignored because the annotation branch in infer_yield_param_types_from_body
#   never consulted call_arg_types).
# D2 (unsound guard): dispatch then synthesized `TRef#==(Pointer)` whose
#   `other.is_a?(self)` narrowing read `load i32 [other+0]` and compared it to
#   the struct's type_id — structs have NO type_id header (offset 0 = first
#   ivar) -> read the field value -> always false.
# In-vivo: Module#intern_type bucket-hit compare `entry[1] == desc.type_params`
# always false -> intern returned the null slot of a fresh ghost entry ->
# s2-hello segfault in block_param_types_fingerprint (null TypeRef element).
# EXPECT: l12_ok

struct TRef
  def initialize(@id : Int32)
  end

  def id : Int32
    @id
  end
end

class Registry
  @buckets = {} of String => Array(Tuple(UInt8, Array(TRef), TRef))

  def intern(name : String, kind : UInt8, params : Array(TRef), fresh : TRef) : TRef
    bucket = @buckets[name]? || begin
      created = [] of Tuple(UInt8, Array(TRef), TRef)
      @buckets[name] = created
      created
    end
    bucket.each do |entry|
      if entry[0] == kind && entry[1] == params
        return entry[2]
      end
    end
    bucket << {kind, params.dup, fresh}
    fresh
  end
end

a = [TRef.new(7)]
b = [TRef.new(7)]
c = [TRef.new(8)]

eq_ok = (a == b) && (a == a) && !(a == c) && (TRef.new(7) == TRef.new(7)) && !(TRef.new(7) == TRef.new(8))

reg = Registry.new
i1 = reg.intern("Pointer(UInt8)", 3_u8, [TRef.new(7)], TRef.new(1118))
# bucket HIT path (the in-vivo failing hop): must return the interned entry
i2 = reg.intern("Pointer(UInt8)", 3_u8, [TRef.new(7)], TRef.new(9999))
# different kind: miss -> new entry
i3 = reg.intern("Pointer(UInt8)", 4_u8, [TRef.new(7)], TRef.new(2222))
intern_ok = i1.id == 1118 && i2.id == 1118 && i3.id == 2222

if eq_ok && intern_ok
  puts "l12_ok"
else
  puts "l12_BAD eq_ok=#{eq_ok} i1=#{i1.id} i2=#{i2.id} i3=#{i3.id}"
end
