require "../ast"

module Adamas
  module Compiler
    module Frontend
      struct RelatedSpan
        getter span : Span
        getter label : String
        getter node_id : ExprId?
        getter file_path : String?

        def initialize(@span : Span, @label : String, @node_id : ExprId? = nil, @file_path : String? = nil)
        end

        def with_file_path(file_path : String?) : self
          RelatedSpan.new(@span, @label, @node_id, file_path)
        end
      end

      struct Diagnostic
        getter message : String
        getter span : Span
        getter node_id : ExprId?
        getter file_path : String?
        getter related_spans : Array(RelatedSpan)

        def initialize(
          @message : String,
          @span : Span,
          @node_id : ExprId? = nil,
          @file_path : String? = nil,
          @related_spans : Array(RelatedSpan) = [] of RelatedSpan
        )
        end

        def with_file_path(file_path : String?, related_spans : Array(RelatedSpan) = @related_spans) : self
          Diagnostic.new(@message, @span, @node_id, file_path, related_spans)
        end

        def to_s(io : IO)
          if file_path = @file_path
            io << file_path << ':'
          end
          io << span.start_line << ':' << span.start_column << " " << message
        end
      end
    end
  end
end
