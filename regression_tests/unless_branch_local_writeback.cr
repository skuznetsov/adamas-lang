# Regression: local mutations inside an unless branch must survive the branch
# merge. `lower_unless` used to save then-branch locals after popping the
# branch scope, restoring the pre-branch value.
#
# EXPECT: unless_branch_local_writeback_ok

plain = 0
unless false
  plain += 1
end
raise "plain" unless plain == 1

wrapping = 0
unless false
  wrapping &+= 1
end
raise "wrapping" unless wrapping == 1

puts "unless_branch_local_writeback_ok"
