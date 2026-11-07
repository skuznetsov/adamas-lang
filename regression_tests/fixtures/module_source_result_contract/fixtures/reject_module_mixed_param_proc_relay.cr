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
  def self.value(flag : Bool) : ModuleSourcePacketRelayEntry.class | ModuleSourcePacketRelayEntry
    if flag
      ModuleSourcePacketRelayEntry
    else
      ModuleSourcePacketRelayEntry.new
    end
  end
end

module ModuleSourcePacketRelay
  def self.send_value(value : T, callback : Proc(ModuleSourcePacketRelayEntry, Int32)) : Int32 forall T
    callback.call(value)
  end
end

callback = Proc(ModuleSourcePacketRelayEntry, Int32).new { |entry| 1 }
ModuleSourcePacketRelay.send_value(
  ModuleSourcePacketRelayFactory.value(true),
  callback,
)
