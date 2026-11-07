class ModuleSourcePacketRelayEntry
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end

  def self.new(&block : self)
    block
  end
end

module ModuleSourcePacketRelayFactory
  def self.value : ModuleSourcePacketRelayEntry.class | ModuleSourcePacketRelayEntry
    ModuleSourcePacketRelayEntry.new
  end
end
callback = Proc(ModuleSourcePacketRelayEntry, Int32).new { |_entry| 1 }
callback.call(ModuleSourcePacketRelayFactory.value)
