require "../ast"

module CrystalV2
  module Compiler
    module Frontend
      struct Diagnostic
        getter message : String
        getter span : Span
        getter node_id : ExprId?
        getter file_path : String?

        def initialize(@message : String, @span : Span, @node_id : ExprId? = nil, @file_path : String? = nil)
        end

        def with_file_path(file_path : String?) : self
          Diagnostic.new(@message, @span, @node_id, file_path)
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
