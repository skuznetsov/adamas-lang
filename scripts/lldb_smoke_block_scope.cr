# Lexical block scope smoke sample for LLDB / DWARF regression.
# Used by scripts/check_lldb_locals.sh — compile with: adamas --debug scripts/lldb_smoke_block_scope.cr -o /tmp/out

a = 1
b = 0
if true
  inner = a + 40
  b = inner
end
puts b
