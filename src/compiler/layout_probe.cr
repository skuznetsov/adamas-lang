# LayoutDecision sidecar: diagnostic-only logger for storage-representation
# decisions made independently by HIR layout, MIR lowering, and the LLVM
# backend. The three "layout oracles" must agree on whether a value of a given
# type is stored as inline bytes, a pointer carrier, or a borrowed address;
# this probe records each decision so divergences can be mapped offline.
#
# Strictly no behavior change when disabled (the default). Enable with
# ADAMAS_LAYOUT_PROBE=1. Output is TSV, one row per unique decision, written
# to ADAMAS_LAYOUT_PROBE_FILE (append) or STDERR when unset.
#
# Row schema (tab-separated):
#   phase       hir | mir | llvm
#   site        decision point (function or branch label)
#   context     field-slot | c-field-slot | field-get | field-set | container-element
#   role        layout | producer | consumer
#   type_name   human-readable type name (catches short/FQ ghost splits)
#   type_id     numeric type id in that phase's registry
#   storage     InlineBytes | PointerCarrier | PointerReference | BorrowedAddress
#   slot_size   bytes reserved at the storage location (-1 unknown)
#   access_size bytes actually read/written by the access (-1 unknown)
#   declared    declared/source type at the site (optional)
#   effective   effective type after overrides at the site (optional)
#
# Storage kinds:
#   InlineBytes      value bytes live at the location itself
#   PointerCarrier   a struct/tuple VALUE is held via heap pointer (V2 legacy ABI)
#   PointerReference a class reference (pointer is the correct representation)
#   BorrowedAddress  access returns the address of inline storage (no load)

module Adamas
  module LayoutProbe
    @@enabled : Bool? = nil
    @@ledger : Bool? = nil
    @@out : ::File? = nil
    @@seen : ::Set(String)? = nil
    @@trace : Array(String)? = nil
    @@seq : Int64 = 0_i64

    # Lazy ENV access inside a method: module-constant ENV reads crash
    # V2-compiled binaries (see CRYSTAL_PATH note in project memory).
    def self.enabled? : Bool
      cached = @@enabled
      return cached unless cached.nil?
      value = ENV["ADAMAS_LAYOUT_PROBE"]?
      enabled = !value.nil? && value != "" && value != "0"
      @@enabled = enabled
      enabled
    end

    # Layout-dependency ledger (B1a0 diagnostic): ADAMAS_LAYOUT_PROBE_LEDGER=1
    # turns on NON-deduplicated, sequence-numbered events recording which owner
    # layouts consumed which field-type sizes (and through which type_size
    # branch). Dedup-free because B1 needs the ORDER of events, not just the
    # set. Requires ADAMAS_LAYOUT_PROBE=1 as well.
    def self.ledger_enabled? : Bool
      cached = @@ledger
      return cached unless cached.nil?
      value = ENV["ADAMAS_LAYOUT_PROBE_LEDGER"]?
      ledger = enabled? && !value.nil? && value != "" && value != "0"
      @@ledger = ledger
      ledger
    end

    # Non-dedup event row: same 11 columns as log() plus a 12th `seq:<n>`
    # column. Order of rows in the file is the order of events.
    def self.log_event(phase : String, site : String, context : String, role : String,
                       type_name : String, type_id : Int64,
                       storage : String, slot_size : Int64, access_size : Int64,
                       declared : String = "", effective : String = "") : Nil
      return unless ledger_enabled?
      seq = @@seq
      @@seq = seq + 1_i64
      io = output
      io << phase << '\t' << site << '\t' << context << '\t' << role << '\t'
      io << type_name << '\t' << type_id << '\t' << storage << '\t'
      io << slot_size << '\t' << access_size << '\t' << declared << '\t' << effective
      io << '\t' << "seq:" << seq << '\n'
      io.flush
      nil
    end

    # Registration-trace filter (B0 diagnostic): ADAMAS_LAYOUT_PROBE_TRACE is a
    # comma-separated list of type-name substrings (e.g. "Slice(UInt8),Atomic(").
    # Registration/update events are logged only for matching names, keeping the
    # hot paths (intern_type, type_size) effectively free when unset.
    def self.trace_enabled? : Bool
      !trace_patterns.empty?
    end

    def self.trace_match?(name : String) : Bool
      pats = trace_patterns
      return false if pats.empty?
      pats.each do |pat|
        return true if name.includes?(pat)
      end
      false
    end

    private def self.trace_patterns : Array(String)
      cached = @@trace
      return cached unless cached.nil?
      pats = [] of String
      if enabled?
        if raw = ENV["ADAMAS_LAYOUT_PROBE_TRACE"]?
          raw.split(',') do |part|
            stripped = part.strip
            pats << stripped unless stripped.empty?
          end
        end
      end
      @@trace = pats
      pats
    end

    def self.log(phase : String, site : String, context : String, role : String,
                 type_name : String, type_id : Int64,
                 storage : String, slot_size : Int64, access_size : Int64,
                 declared : String = "", effective : String = "") : Nil
      return unless enabled?
      # Ledger mode needs EVENT ORDER, so dedup would hide exactly what B1
      # diagnostics look for (repeated registrations, re-resolutions). Route
      # every row through the sequence-numbered non-dedup writer instead.
      if ledger_enabled?
        log_event(phase, site, context, role, type_name, type_id,
          storage, slot_size, access_size, declared, effective)
        return
      end
      row = String.build do |io|
        io << phase << '\t' << site << '\t' << context << '\t' << role << '\t'
        io << type_name << '\t' << type_id << '\t' << storage << '\t'
        io << slot_size << '\t' << access_size << '\t' << declared << '\t' << effective
      end
      seen = @@seen ||= ::Set(String).new
      return if seen.includes?(row)
      seen << row
      io = output
      io << row << '\n'
      io.flush
      nil
    end

    private def self.output : IO
      if file = @@out
        return file
      end
      if path = ENV["ADAMAS_LAYOUT_PROBE_FILE"]?
        file = ::File.open(path, "a")
        @@out = file
        file
      else
        STDERR
      end
    end
  end
end
