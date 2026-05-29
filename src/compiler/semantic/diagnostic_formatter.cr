require "./diagnostic"
require "../frontend/diagnostic_formatter"

module Adamas
  module Compiler
    module Semantic
      module DiagnosticFormatter
        # Format a semantic diagnostic with Rust-style multi-span output
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
          primary_source = yield diagnostic.primary_file_path

          String.build do |io|
            # Header: error[E2001]: message
            io << format_level(diagnostic.level)
            io << "[" << diagnostic.code << "]: "
            io << diagnostic.message << "\n"

            # Primary span with source snippet
            if primary_source
              io << format_primary_span(primary_source, diagnostic.primary_span, diagnostic.primary_file_path)

              # Secondary spans (notes)
              diagnostic.secondary_spans.each do |sec|
                io << "\n"
                io << "note: " << sec.label << "\n"
                secondary_source = sec.file_path == diagnostic.primary_file_path ? primary_source : yield sec.file_path
                io << format_secondary_span(secondary_source, sec.span, sec.file_path)
              end
            else
              # No source available, just show location
              io << "  --> " << format_location(diagnostic.primary_span, diagnostic.primary_file_path) << "\n"
            end
          end
        end

        private def self.format_level(level : DiagnosticLevel) : String
          case level
          when .error?   then "error"
          when .warning? then "warning"
          when .info?    then "info"
          else                "unknown"
          end
        end

        private def self.format_location(span : Frontend::Span, file_path : String? = nil) : String
          location = "#{span.start_line}:#{span.start_column}"
          file_path ? "#{file_path}:#{location}" : location
        end

        private def self.format_primary_span(source : String, span : Frontend::Span, file_path : String? = nil) : String
          String.build do |io|
            io << "  --> " << format_location(span, file_path) << "\n"
            io << format_snippet(source, span)
          end
        end

        private def self.format_secondary_span(source : String?, span : Frontend::Span, file_path : String? = nil) : String
          String.build do |io|
            io << "  --> " << format_location(span, file_path) << "\n"
            if source
              io << format_snippet(source, span)
            end
          end
        end

        private def self.format_snippet(source : String, span : Frontend::Span) : String
          # Extract relevant lines from source
          lines = source.lines
          start_line = span.start_line
          end_line = span.end_line

          # Clamp to valid range
          start_index = (start_line - 1).clamp(0, lines.size - 1)
          end_index = (end_line - 1).clamp(start_index, lines.size - 1)

          # Build snippet with line numbers and underlines
          snippet_lines = lines[start_index..end_index]
          gutter_width = end_line.to_s.size

          String.build do |io|
            snippet_lines.each_with_index do |line, idx|
              line_num = start_line + idx

              # Line with code
              io << "   " << line_num.to_s.rjust(gutter_width) << " | "
              io << line.rstrip("\n") << "\n"

              # Underline (only if within span)
              if line_num >= span.start_line && line_num <= span.end_line
                underline = build_underline(
                  line,
                  line_num,
                  span,
                  snippet_lines.size
                )
                if underline.size > 0
                  io << "   " << " " * gutter_width << " | "
                  io << underline << "\n"
                end
              end
            end
          end
        end

        private def self.build_underline(
          line : String,
          line_num : Int32,
          span : Frontend::Span,
          total_lines : Int32
        ) : String
          length = line.size

          if total_lines == 1
            # Single line span
            start_col = (span.start_column - 1).clamp(0, length)
            end_col = (span.end_column - 1).clamp(start_col, length)
            caret_count = end_col - start_col
            caret_count = 1 if caret_count <= 0

            String.build do |io|
              io << " " * start_col
              io << "^" * caret_count
            end
          elsif line_num == span.start_line
            # First line of multi-line span
            start_col = (span.start_column - 1).clamp(0, length)
            caret_count = length - start_col
            caret_count = 1 if caret_count <= 0

            String.build do |io|
              io << " " * start_col
              io << "^" * caret_count
            end
          elsif line_num == span.end_line
            # Last line of multi-line span
            end_col = (span.end_column - 1).clamp(0, length)
            caret_count = end_col
            caret_count = 1 if caret_count <= 0

            "^" * caret_count
          else
            # Middle line of multi-line span
            "^" * length
          end
        end
      end
    end
  end
end
