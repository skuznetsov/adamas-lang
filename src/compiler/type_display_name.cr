# Crystal's spelling of a type name for user-visible strings.
#
# Canonical V2 union names put `Nil` first (normalize_union_type_name), which
# keys mangling, registries and caches. Crystal's `UnionType#to_s` moves `Nil`
# to the end of every union, also inside generic arguments:
# `typeof(x)` → `(Int32 | Nil)`, `[1, nil].class` → `Array(Int32 | Nil)`.
# Crystal never prints a root anchor either: a source spelling such as
# `Array(::Int32 | ::Nil)` shows as `Array(Int32 | Nil)`. Member order is
# otherwise kept (Crystal orders union members by type identity, not name).
# Only strings shown to the program use this spelling.
module Adamas
  module TypeDisplayName
    def self.crystal(name : String) : String
      return name unless name.includes?("Nil") || root_anchored?(name)
      display(name)
    end

    private def self.root_anchored?(name : String) : Bool
      name.starts_with?("::") || name.includes?("(::") || name.includes?(" ::")
    end

    private def self.display(text : String) : String
      stripped = text.strip
      stripped = stripped.byte_slice(2, stripped.bytesize - 2) if stripped.starts_with?("::")
      return stripped if stripped.empty?
      if stripped.starts_with?('(') && matching_close(stripped, 0) == stripped.bytesize - 1
        return "(#{display(stripped.byte_slice(1, stripped.bytesize - 2))})"
      end
      parts = split_top_level(stripped, '|')
      if parts.size > 1
        nil_parts = [] of String
        other_parts = [] of String
        parts.each do |part|
          shown = display(part)
          if shown == "Nil" || shown == "::Nil"
            nil_parts << shown
          else
            other_parts << shown
          end
        end
        return (other_parts + nil_parts).join(" | ")
      end
      open = stripped.byte_index('('.ord)
      return stripped unless open
      close = matching_close(stripped, open)
      return stripped unless close
      head = stripped.byte_slice(0, open)
      tail = stripped.byte_slice(close + 1, stripped.bytesize - close - 1)
      args = split_top_level(stripped.byte_slice(open + 1, close - open - 1), ',').map do |arg|
        display_argument(arg)
      end
      "#{head}(#{args.join(", ")})#{tail}"
    end

    # NamedTuple arguments are `key: Type`.
    private def self.display_argument(arg : String) : String
      stripped = arg.strip
      if colon = named_key_end(stripped)
        "#{stripped.byte_slice(0, colon + 1)} #{display(stripped.byte_slice(colon + 1, stripped.bytesize - colon - 1))}"
      else
        display(stripped)
      end
    end

    private def self.named_key_end(text : String) : Int32?
      index = 0
      bytes = text.to_slice
      while index < bytes.size
        byte = bytes[index]
        if byte == ':'.ord
          return nil if index + 1 < bytes.size && bytes[index + 1] == ':'.ord
          return index > 0 ? index : nil
        end
        return nil unless byte == '_'.ord || (byte >= 'a'.ord && byte <= 'z'.ord) ||
                          (byte >= 'A'.ord && byte <= 'Z'.ord) || (byte >= '0'.ord && byte <= '9'.ord)
        index += 1
      end
      nil
    end

    private def self.matching_close(text : String, open : Int32) : Int32?
      depth = 0
      bytes = text.to_slice
      index = open
      while index < bytes.size
        byte = bytes[index]
        if byte == '('.ord
          depth += 1
        elsif byte == ')'.ord
          depth -= 1
          return index if depth == 0
        end
        index += 1
      end
      nil
    end

    private def self.split_top_level(text : String, separator : Char) : Array(String)
      parts = [] of String
      depth = 0
      start = 0
      bytes = text.to_slice
      index = 0
      while index < bytes.size
        byte = bytes[index]
        if byte == '('.ord
          depth += 1
        elsif byte == ')'.ord
          depth -= 1
        elsif byte == separator.ord && depth == 0
          parts << text.byte_slice(start, index - start)
          start = index + 1
        end
        index += 1
      end
      parts << text.byte_slice(start, bytes.size - start)
      parts
    end
  end
end
