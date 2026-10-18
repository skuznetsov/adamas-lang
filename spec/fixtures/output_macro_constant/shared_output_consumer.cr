require "./shared_output_constants"

module SharedOutputMacroConsumer
  def self.values
    {
      "first"  => SharedOutputMacroSource::VALUE,
      "second" => SharedOutputMacroSource::VALUE,
      "third"  => SharedOutputMacroSource::VALUE,
      "fourth" => SharedOutputMacroSource::VALUE,
    }
  end
end

values = SharedOutputMacroConsumer.values
puts values["first"]
puts values["second"]
puts values["third"]
puts values["fourth"]
