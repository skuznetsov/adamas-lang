require "../frontend/ast"

module Adamas
  module Compiler
    module Semantic
      # Severity levels for semantic diagnostics
      enum DiagnosticLevel
        Error   # Compilation must fail
        Warning # Can continue, but suspicious
        Info    # Informational, no action needed
      end

      # Rich diagnostic with primary + secondary locations (Rust-style)
      struct Diagnostic
        getter level : DiagnosticLevel
        getter code : String              # e.g., "E2001", "W2001"
        getter message : String
        getter primary_span : Frontend::Span
        getter primary_node_id : Frontend::ExprId?
        getter primary_file_path : String?
        getter secondary_spans : Array(SecondarySpan)

        def initialize(
          @level : DiagnosticLevel,
          @code : String,
          @message : String,
          @primary_span : Frontend::Span,
          @secondary_spans : Array(SecondarySpan) = [] of SecondarySpan,
          @primary_node_id : Frontend::ExprId? = nil,
          @primary_file_path : String? = nil,
        )
        end

        def with_paths(primary_file_path : String?, secondary_spans : Array(SecondarySpan) = @secondary_spans) : self
          Diagnostic.new(
            @level,
            @code,
            @message,
            @primary_span,
            secondary_spans,
            @primary_node_id,
            primary_file_path,
          )
        end
      end

      # Secondary location with annotation (e.g., "previous definition here")
      struct SecondarySpan
        getter span : Frontend::Span
        getter label : String  # "previous definition", "shadowed here", etc.
        getter node_id : Frontend::ExprId?
        getter file_path : String?

        def initialize(@span : Frontend::Span, @label : String, @node_id : Frontend::ExprId? = nil, @file_path : String? = nil)
        end

        def with_file_path(file_path : String?) : self
          SecondarySpan.new(@span, @label, @node_id, file_path)
        end
      end
    end
  end
end
