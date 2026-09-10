require "path"

def emit(label : String, path : Path) : Nil
  puts "#{label}|#{path.to_s}|end=#{path.ends_with_separator? ? 1 : 0}"
end

def emit_join(label : String, path : Path, part : String) : Nil
  emit(label, path.join(part))
end

def emit_join_tuple(label : String, path : Path, parts : Tuple(String, String)) : Nil
  emit(label, path.join(*parts))
end

# Direct constructors: POSIX/Windows and plain, slash, backslash suffixes.
emit("posix.plain", Path.posix("foo"))
emit("posix.slash", Path.posix("foo/"))
emit("posix.backslash", Path.posix("foo\\"))
emit("windows.plain", Path.windows("foo"))
emit("windows.slash", Path.windows("foo/"))
emit("windows.backslash", Path.windows("foo\\"))

# Single-part joins cover plain names and starts-with-separator cases.
emit_join("posix.join.plain", Path.posix("root"), "leaf")
emit_join("posix.join.slash", Path.posix("root/"), "/leaf")
emit_join("posix.join.backslash", Path.posix("root"), "\\leaf")
emit_join("windows.join.plain", Path.windows("root"), "leaf")
emit_join("windows.join.slash", Path.windows("root/"), "/leaf")
emit_join("windows.join.backslash", Path.windows("root\\"), "\\leaf")

# Valid multi-part join splat control.
emit_join_tuple("posix.join.tuple", Path.posix("root"), {"mid", "leaf"})
emit_join_tuple("windows.join.tuple", Path.windows("root"), {"mid", "leaf"})
