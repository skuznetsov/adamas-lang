require "proc"

lib ProcNewSelfDiagnosticOutput
  fun putchar(value : Int32) : Int32
end

struct Proc
  def self.new(&block : self)
    67_i32
  end
end

value = Proc(Int32, Int32).new { |input| input }
ProcNewSelfDiagnosticOutput.putchar(value)
ProcNewSelfDiagnosticOutput.putchar(10_i32)
