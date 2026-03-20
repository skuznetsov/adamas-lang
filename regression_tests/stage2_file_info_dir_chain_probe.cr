path = ARGV[0]? || "."

result = if info = File.info?(path, follow_symlinks: true)
  info.type.directory?
else
  false
end

puts result
