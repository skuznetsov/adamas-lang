require "./span"
require "./parser/diagnostic"

module CrystalV2
  module Compiler
    module Frontend
      module DiagnosticFormatter
        def self.format(source : String?, diagnostic : Diagnostic) : String
          format_with_sources(diagnostic) { |_path| source }
        end

        def self.format(sources : Hash(String, String), diagnostic : Diagnostic) : String
          format_with_sources(diagnostic) do |path|
            next nil unless path
            sources[path]?
          end
        end

        private def self.format_with_sources(diagnostic : Diagnostic, &source_lookup : String? -> String?) : String
          span = diagnostic.span
          source = yield diagnostic.file_path
          range = format_range(span, diagnostic.file_path)
          base = String.build do |io|
            io << range << " " << diagnostic.message
          end

          return base unless source && span

          snippet_lines = extract_lines(source, span)
          return base if snippet_lines.empty?

          gutter_width = (span.end_line).to_s.size
          underline_lines = build_underlines(snippet_lines, span)

          snippet = build_snippet(snippet_lines, underline_lines, span, gutter_width)
          String.build do |io|
            io << base << '\n'
            io << snippet
          end
        end

        private def self.format_range(span : Span, file_path : String? = nil) : String
          range = "#{span.start_line}:#{span.start_column}-#{span.end_line}:#{span.end_column}"
          file_path ? "#{file_path}:#{range}" : range
        end

        private def self.extract_lines(source : String, span : Span) : Array(String)
          lines = source.lines
          start_index = span.start_line - 1
          end_index = span.end_line - 1
          return [] of String unless start_index >= 0 && end_index < lines.size
          lines[start_index..end_index]
        end

        private def self.build_snippet(lines : Array(String), underlines : Array(String), span : Span, gutter_width : Int32) : String
          start_line_index = span.start_line
          String.build do |io|
            lines.each_with_index do |line, index|
              line_number = start_line_index + index
              io << format_gutter(line_number, gutter_width, true) << line.rstrip("\n") << '\n'
              underline = underlines[index]
              if underline.size > 0
                io << format_gutter(nil, gutter_width, false) << underline << '\n'
              end
            end
          end.rstrip
        end

        private def self.format_gutter(line_number : Int32?, width : Int32, is_code_line : Bool) : String
          if line_number
            String.build do |io|
              io << "  " << line_number.to_s.rjust(width) << " | "
            end
          else
            # Align "|" with the line number gutter
            String.build { |io| io << " " * (width + 3) << "| " }
          end
        end

        private def self.build_underlines(lines : Array(String), span : Span) : Array(String)
          return [] of String if lines.empty?
          count = lines.size

          lines.map_with_index do |line, index|
            if count == 1
              underline_segment(line, span.start_column, span.end_column)
            elsif index == 0
              underline_segment(line, span.start_column, line.size + 1)
            elsif index == count - 1
              underline_segment(line, 1, span.end_column + 1)
            else
              underline_segment(line, 1, line.size + 1)
            end
          end
        end

        private def self.underline_segment(line : String, start_column : Int32, end_column : Int32) : String
          length = line.size
          start_index = (start_column - 1).clamp(0, length)
          end_index = (end_column - 1).clamp(start_index, length)
          caret_count = end_index - start_index
          caret_count = 1 if caret_count <= 0
          available = length - start_index
          if available <= 0
            start_index = length
            available = 0
          end
          if available > 0 && caret_count > available
            caret_count = available
          end
          caret_count = 1 if caret_count <= 0
          String.build do |io|
            io << " " * start_index
            io << "^" * caret_count
          end
        end
      end
    end
  end
end
