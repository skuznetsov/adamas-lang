def foo(path, follow_symlinks)
  if info = File.info?(path, follow_symlinks: follow_symlinks)
    info.type.directory?
  else
    false
  end
end

puts foo(".", true)
