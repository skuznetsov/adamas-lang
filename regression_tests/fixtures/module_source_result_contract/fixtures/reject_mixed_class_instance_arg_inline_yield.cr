class ModuleSourcePacketMixedEntry
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end

  def self.new(&block : self)
    block
  end
end

module ModuleSourcePacketMixedKinds
  def self.value(flag : Bool) : ModuleSourcePacketMixedEntry.class | ModuleSourcePacketMixedEntry
    if flag
      ModuleSourcePacketMixedEntry
    else
      ModuleSourcePacketMixedEntry.new
    end
  end
end

def module_source_packet_mixed_inline(&block : -> T) : T forall T
  yield
end

def module_source_packet_send_mixed_instance(callback : Proc(ModuleSourcePacketMixedEntry, Int32), &block : -> T) : Int32 forall T
  callback.call(module_source_packet_mixed_inline { yield })
end

callback = Proc(ModuleSourcePacketMixedEntry, Int32).new { |entry| 1 }
module_source_packet_send_mixed_instance(callback) do
  ModuleSourcePacketMixedKinds.value(true)
end
