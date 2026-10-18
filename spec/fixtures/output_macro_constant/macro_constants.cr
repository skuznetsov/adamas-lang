module DeferredMacroSource
  VERSION = {{ `echo v1.2.3`.chomp.stringify.gsub(/^v/, "") }}
  DIRECT_TEXT = {{ "direct" }}
  DIRECT_NUMBER = {{ 42 }}
  DIRECT_BOOL = {{ true }}
  GROUPED_TEXT = ({{ "grouped" }})
end
