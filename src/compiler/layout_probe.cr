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

    # Divergence assert (step 0 of the ABI rework, see docs/abi_rework_quadr_plan.md).
    # ADAMAS_LAYOUT_ASSERT=1   -> emit SLOT-CONFLICT rows (same (type, context),
    #                            different slot size across phases — the operational
    #                            repr-flip, plan §2.7) AND DIVERGENCE rows (the
    #                            label signal, report-only).
    # ADAMAS_LAYOUT_ASSERT=abort -> additionally abort on the first SLOT-CONFLICT
    #                            (use as a hard regression gate in later steps). The
    #                            label DIVERGENCE never aborts: the 2026-06-16
    #                            measurement found it is mostly cross-context label
    #                            noise (slot agrees, only the storage NAME differs).
    # Requires ADAMAS_LAYOUT_PROBE=1. Storage classes labelled: InlineBytes /
    # PointerCarrier / PointerReference. BorrowedAddress is an access mode (a
    # field-get returning an address), not a storage class, so it is ignored in
    # the label signal and reports slot=-1 (skipped by the slot-conflict signal).
    @@assert_mode : Int32 = -1 # -1 unknown, 0 off, 1 report, 2 abort
    @@storage_seen : Hash(String, ::Set(String))? = nil
    @@diverged : ::Set(String)? = nil
    # Operational metric (plan §2.7): per (type, context) the slot sizes recorded
    # by each phase. A same-context slot-size disagreement across phases is the
    # real producer/consumer repr-flip (cb25a911 family); a cross-CONTEXT repr
    # difference (struct field=inline vs container element=pointer) is the legacy
    # ABI by design, NOT a same-context conflict.
    @@slot_seen : Hash(String, Hash(Int64, ::Set(String)))? = nil
    @@slot_conflict : ::Set(String)? = nil

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

    # Assert mode: 0 off, 1 report-only, 2 abort-on-first.
    def self.assert_mode : Int32
      cached = @@assert_mode
      return cached unless cached < 0
      mode = 0
      if enabled?
        case ENV["ADAMAS_LAYOUT_ASSERT"]?
        when nil, "", "0" then mode = 0
        when "abort", "2" then mode = 2
        else                   mode = 1
        end
      end
      @@assert_mode = mode
      mode
    end

    # Two signals (refined per plan §2.7 after the 2026-06-16 measurement found
    # the type-keyed label assert measures cross-CONTEXT label noise, not the
    # operational bug):
    #
    #  (1) SLOT-CONFLICT — the OPERATIONAL invariant. For the SAME (type,
    #      context), >= 2 distinct slot sizes were recorded (intra- OR
    #      cross-phase) => a producer/consumer disagreement on "pointer (8) or
    #      N-byte value" (the cb25a911 repr-flip / Zone ghost-slot family). This
    #      is the hard signal; aborts in mode 2.
    #  (2) DIVERGENCE — the LABEL signal, REPORT-ONLY (never aborts). The old
    #      type-keyed storage-class divergence. Verified mostly cross-context
    #      label noise (String/Fiber: slot agrees across phases, only the
    #      storage-class NAME differs), so it is informative, not a gate.
    private def self.check_divergence(phase : String, context : String,
                                      type_name : String, storage : String,
                                      slot_size : Int64) : Nil
      return if type_name.empty? || type_name == "Unknown"

      # (1) Operational slot-size conflict per (type, context). BorrowedAddress
      # and other address modes report slot_size = -1 (no stored size), so a
      # negative slot is skipped — only real reserved sizes are compared.
      if slot_size >= 0
        key = "#{type_name}#{context}"
        by_slot = (@@slot_seen ||= Hash(String, Hash(Int64, ::Set(String))).new)[key] ||=
          Hash(Int64, ::Set(String)).new
        (by_slot[slot_size] ||= ::Set(String).new) << phase
        if by_slot.size >= 2
          # No phase-count gate: a (type, context) with >= 2 distinct slot
          # sizes is a conflict whether the sizes come from ONE phase (the
          # cb25a911 intra-LLVM container stride family, or the Zone 16-vs-24
          # intra-HIR ghost slot) or from two. Cross-CONTEXT differences (field
          # inline vs container pointer) never reach here — the key includes
          # context. The outer `by_slot.size >= 2` already gates; this inner
          # check is the same guard, kept for the dedup/emit block below.
          if by_slot.size >= 2
            sig = "#{key}|#{by_slot.keys.sort.join(",")}"
            conflict = @@slot_conflict ||= ::Set(String).new
            unless conflict.includes?(sig)
              conflict << sig
              desc = by_slot.to_a.sort_by { |sz, _| sz }
                .map { |sz, ph_set| "#{ph_set.to_a.sort.join("/")}=#{sz}" }.join(" ")
              io = output
              io << "SLOT-CONFLICT\t" << type_name << '\t' << context << '\t' << desc << '\n'
              io.flush
              if assert_mode == 2
                raise "LAYOUT SLOT-SIZE CONFLICT for #{type_name} in #{context}: " \
                      "#{desc} (ADAMAS_LAYOUT_ASSERT=abort)"
              end
            end
          end
        end
      end

      # (2) Label divergence (report-only). BorrowedAddress is an access mode,
      # not a storage class.
      return if storage == "BorrowedAddress"
      seen = @@storage_seen ||= Hash(String, ::Set(String)).new
      bucket = seen[type_name] ||= ::Set(String).new
      before = bucket.size
      bucket << "#{phase}=#{storage}"
      return if bucket.size == before # nothing new for this type

      # Distinct storage classes (across all phases/sites) and distinct phases.
      classes = ::Set(String).new
      phases = ::Set(String).new
      bucket.each do |entry|
        ph, _, st = entry.partition('=')
        phases << ph
        classes << st
      end
      return if classes.size < 2 # all decisions agree so far

      # Re-emit when the bucket grows (a new phase/class joins), deduped on the
      # full signature. INTRA = one phase self-disagrees (the B0-2 ordering
      # hole); CROSS = phases disagree (the 3-oracle label split).
      sig = bucket.to_a.sort.join(",")
      diverged = @@diverged ||= ::Set(String).new
      return if diverged.includes?(sig)
      diverged << sig
      kind = phases.size >= 2 ? "CROSS" : "INTRA"
      io = output
      io << "DIVERGENCE\t" << kind << '\t' << type_name << '\t' << bucket.to_a.sort.join(" ") << '\n'
      io.flush
      nil
    end

    def self.log(phase : String, site : String, context : String, role : String,
                 type_name : String, type_id : Int64,
                 storage : String, slot_size : Int64, access_size : Int64,
                 declared : String = "", effective : String = "") : Nil
      return unless enabled?
      check_divergence(phase, context, type_name, storage, slot_size) if assert_mode > 0
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
