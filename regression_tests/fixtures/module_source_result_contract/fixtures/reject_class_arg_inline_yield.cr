class ModuleSourcePacketEntry
end

struct Proc
  @[Primitive(:proc_call)]
  def call(*args : *T) : R
  end

  def self.new(&block : self)
    block
  end
end

module ModuleSourcePacketKinds
  def self.class_value : ModuleSourcePacketEntry.class
    ModuleSourcePacketEntry
  end
end

def module_source_packet_inline(&block : -> T) : T forall T
  yield
end

def module_source_packet_send_instance(callback : Proc(ModuleSourcePacketEntry, Int32), &block : -> T) : Int32 forall T
  callback.call(module_source_packet_inline { yield })
end

callback = Proc(ModuleSourcePacketEntry, Int32).new { |entry| 1 }
module_source_packet_send_instance(callback) do
  ModuleSourcePacketKinds.class_value
end
