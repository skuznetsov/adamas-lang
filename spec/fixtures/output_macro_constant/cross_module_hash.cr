require "./macro_constants"

module DeferredMacroConsumer
  def self.labels
    {
      "version" => DeferredMacroSource::VERSION,
      "direct" => DeferredMacroSource::DIRECT_TEXT,
      "grouped" => DeferredMacroSource::GROUPED_TEXT,
    }
  end
end

labels = DeferredMacroConsumer.labels
puts labels["version"]
puts labels["direct"]
puts labels["grouped"]
puts DeferredMacroSource::DIRECT_NUMBER
puts DeferredMacroSource::DIRECT_BOOL
