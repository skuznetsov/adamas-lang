@[Link("c")]
lib NamedEvaluation
  fun write(fd : Int32, buffer : Void*, count : UInt64) : Int64
end

def named_fd : Int32
  NamedEvaluation.write(1, "F", 1_u64)
  1
end

def named_buffer : String
  NamedEvaluation.write(1, "B", 1_u64)
  "X\n"
end

def named_count : UInt64
  NamedEvaluation.write(1, "C", 1_u64)
  2_u64
end

# Crystal normalizes named lib arguments into declaration order before execution.
NamedEvaluation.write(count: named_count, buffer: named_buffer, fd: named_fd)
