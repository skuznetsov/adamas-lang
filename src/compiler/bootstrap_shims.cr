# Temporary bootstrap shim for stage1 mis-lowering in DWARF line table code.
#
# In self-host stage1 builds, some `format.lnct` calls from stdlib can degrade
# to unresolved bare calls `lnct(format)`, which breaks linking (`_lnct`).
# Keeping this top-level fallback unblocks stage2 bootstrap while we continue
# narrowing the underlying lowering bug.
def lnct(_value)
  0_i64
end

# Some bad lowerings lose the receiver *and* argument and emit bare `lnct()`.
def lnct
  0_i64
end

module Adamas::Compiler::BootstrapEnv
  def self.get?(key : String) : String?
    # V2 BOOTSTRAP: ENV module constant access crashes V2-compiled binaries.
    # Use LibC.getenv directly to bypass ENV completely.
    ptr = LibC.getenv(key.to_unsafe)
    if ptr.null?
      nil
    else
      String.new(ptr)
    end
  end

  def self.get(key : String, default : String) : String
    get?(key) || default
  end

  def self.enabled?(key : String) : Bool
    !get?(key).nil?
  end

  # Keep the CLI's MIR policy and LLVM's emission policy on one bounded value.
  # Parallel worker emission is an explicit opt-in; an absent, malformed, or
  # non-positive override must therefore select the serial path.
  def self.llvm_worker_count : Int32
    raw = get?("ADAMAS_LLVM_WORKERS")
    return 1 unless raw

    requested = raw.to_i?
    return 1 unless requested && requested > 0
    return 8 if requested > 8
    requested.to_i32
  end
end
