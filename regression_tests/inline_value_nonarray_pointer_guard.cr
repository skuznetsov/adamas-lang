struct Disc
  getter tag : Int32
  getter payload : Int32
  def initialize(@tag : Int32, @payload : Int32)
  end
end

# Disc is a leaf-POD struct (InlineValueCopy candidate) used ONLY via a raw
# Pointer(Disc) value load/store, NEVER inside an Array. This is the non-Array
# Pointer(T)#value path the refuted type-driven slice wrongly inline-loaded
# (the IO#gets_peek `switch i32` blocker). The A' safe-set must leave it boxed:
# never inline_value_safe (bv=0), the GEP never array_buffer_value.
p = Pointer(Disc).malloc(1_u64)
p.value = Disc.new(7, 42)
d = p.value
out = case d.tag
      when 7 then d.payload
      else 0
      end
STDERR.puts "out=#{out}"
STDOUT.flush
exit(0)
