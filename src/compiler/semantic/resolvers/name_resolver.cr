require "../../frontend/ast"
require "../../frontend/parser/diagnostic"
require "../symbol_table"
require "../symbol"

module CrystalV2
  module Compiler
    module Semantic
      class NameResolver
        BLOCK_SYMBOL_NODE_ID = Frontend::ExprId.new(-1)
        alias Program = Frontend::Program
        alias ExprId = Frontend::ExprId
        alias Diagnostic = Frontend::Diagnostic

        @root_table : SymbolTable
        @current_table : SymbolTable
        @namespace_stack : Array(Symbol)
        @class_body_meta_lookup_stack : Array(SymbolTable)
        @current_method_is_class_method_stack : Array(Bool)
        @bare_statement_candidate_stack : Array(ExprId)
        @call_callee_depth : Int32
        @type_expression_depth : Int32

        struct Result
          getter identifier_symbols : Hash(ExprId, Symbol)
          getter diagnostics : Array(Diagnostic)

          def initialize(@identifier_symbols : Hash(ExprId, Symbol), @diagnostics : Array(Diagnostic))
          end
        end

        def initialize(@program : Program, root_table : SymbolTable, @extra_roots : Array(ExprId) = [] of ExprId)
          @arena = @program.ast_arena
          @string_pool = @program.string_pool
          @root_table = root_table
          @identifier_symbols = {} of ExprId => Symbol
          @diagnostics = [] of Diagnostic
          @current_table = @root_table
          @namespace_stack = [] of Symbol
          @class_body_meta_lookup_stack = [] of SymbolTable
          @current_method_is_class_method_stack = [] of Bool
          @bare_statement_candidate_stack = [] of ExprId
          @call_callee_depth = 0
          @type_expression_depth = 0
        end

        def resolve : Result
          @current_table = @root_table
          each_analysis_root do |root_id|
            visit(root_id)
          end
          Result.new(@identifier_symbols, @diagnostics)
        end

        private def each_analysis_root(& : ExprId ->)
          @program.roots.each { |root_id| yield root_id }
          @extra_roots.each { |root_id| yield root_id }
        end

        private def visit(node_id : ExprId)
          return if node_id.invalid?
          node = @arena[node_id]

          case Frontend.node_kind(node)
          when Frontend::NodeKind::Identifier
            resolve_identifier(node_id, node.as(Frontend::IdentifierNode))
          when Frontend::NodeKind::Self
            resolve_self(node_id)
          when Frontend::NodeKind::InstanceVar
            resolve_instance_var(node_id, node.as(Frontend::InstanceVarNode))
          when Frontend::NodeKind::ClassVar
            resolve_class_var(node_id, node.as(Frontend::ClassVarNode))
          when Frontend::NodeKind::Global
            resolve_global_var(node_id, node.as(Frontend::GlobalNode))
          when Frontend::NodeKind::Assign
            assign = node.as(Frontend::AssignNode)
            # Visit the value first (it may reference existing variables)
            visit(assign.value)
            # Then handle the target (which declares a new variable if it's an identifier)
            handle_assign_target(assign.target)
          when Frontend::NodeKind::MultipleAssign
            assign = node.as(Frontend::MultipleAssignNode)
            visit(assign.value)
            assign.targets.each do |target_id|
              handle_assign_target(target_id)
            end
          when Frontend::NodeKind::TypeDeclaration
            visit_type_declaration(node.as(Frontend::TypeDeclarationNode))
          when Frontend::NodeKind::Out
            visit_out(node_id, node.as(Frontend::OutNode))
          when Frontend::NodeKind::MemberAccess
            visit(node.as(Frontend::MemberAccessNode).object)
          when Frontend::NodeKind::Call
            call = node.as(Frontend::CallNode)
            if skip_macro_call?(call)
              return
            end
            if type_application_call?(call)
              visit_type_application_call(call)
              return
            end
            if callee_id = call.callee
              @call_callee_depth += 1
              begin
                visit(callee_id)
              ensure
                @call_callee_depth -= 1
              end
            end
            call.args.each_with_index do |arg, index|
              if call_type_expression_arg?(call, index)
                visit_type_expression(arg)
              else
                visit(arg)
              end
            end
            if block_id = call.block
              visit(block_id)
            end
            call.named_args.try &.each { |named| visit(named.value) }
          when Frontend::NodeKind::Unary
            case node
            when Frontend::UnaryNode
              if String.new(node.operator) == "->"
                visit_proc_pointer(node)
              else
                visit(node.operand)
              end
            when Frontend::SplatNode
              visit(node.expr)
            end
          when Frontend::NodeKind::Binary
            binary = node.as(Frontend::BinaryNode)
            visit(binary.left)
            visit(binary.right)
          when Frontend::NodeKind::Grouping
            visit(node.as(Frontend::GroupingNode).expression)
          when Frontend::NodeKind::Index
            index = node.as(Frontend::IndexNode)
            visit(index.object)
            if enum_symbol = resolved_enum_symbol(index.object)
              with_enum_index_scope(enum_symbol) do
                index.indexes.each { |expr_id| visit(expr_id) }
              end
            else
              index.indexes.each { |expr_id| visit(expr_id) }
            end
          when Frontend::NodeKind::Range
            range = node.as(Frontend::RangeNode)
            visit(range.begin_expr)
            visit(range.end_expr)
          when Frontend::NodeKind::VisibilityModifier
            visit(node.as(Frontend::VisibilityModifierNode).expression)
          when Frontend::NodeKind::MacroExpression
            # Source macro DSL is handled by macro expansion and generated roots.
            # Running regular name resolution inside {{ ... }} mostly reports
            # false unresolved identifiers like flag?, skip_file, and macro
            # type parameters from the unexpanded source.
          when Frontend::NodeKind::MacroLiteral
            visit_macro_literal(node.as(Frontend::MacroLiteralNode))
          when Frontend::NodeKind::MacroDef
            # Body handled via MacroLiteral; skip definition node
          when Frontend::NodeKind::Begin
            visit_begin(node.as(Frontend::BeginNode))
          when Frontend::NodeKind::Raise
            visit_raise(node.as(Frontend::RaiseNode))
          when Frontend::NodeKind::StringInterpolation
            visit_string_interpolation(node.as(Frontend::StringInterpolationNode))
          when Frontend::NodeKind::Def
            visit_def(node_id, node.as(Frontend::DefNode))
          when Frontend::NodeKind::Class,
               Frontend::NodeKind::Struct,
               Frontend::NodeKind::Union
            visit_class(node_id, node.as(Frontend::ClassNode))
          when Frontend::NodeKind::Module
            visit_module(node_id, node.as(Frontend::ModuleNode))
          when Frontend::NodeKind::Enum
            visit_enum(node_id, node.as(Frontend::EnumNode))
          when Frontend::NodeKind::Constant
            visit(node.as(Frontend::ConstantNode).value)
          when Frontend::NodeKind::Case
            visit_case(node.as(Frontend::CaseNode))
          when Frontend::NodeKind::If
            visit_if(node.as(Frontend::IfNode))
          when Frontend::NodeKind::Unless
            visit_unless(node.as(Frontend::UnlessNode))
          when Frontend::NodeKind::While
            visit_while(node.as(Frontend::WhileNode))
          when Frontend::NodeKind::Until
            visit_until(node.as(Frontend::UntilNode))
          when Frontend::NodeKind::Loop
            visit_loop(node.as(Frontend::LoopNode))
          when Frontend::NodeKind::Block
            visit_block(node.as(Frontend::BlockNode))
          when Frontend::NodeKind::ProcLiteral
            visit_proc_literal(node.as(Frontend::ProcLiteralNode))
          when Frontend::NodeKind::Yield
            visit_yield(node.as(Frontend::YieldNode))
          when Frontend::NodeKind::IsA
            visit_is_a(node.as(Frontend::IsANode))
          when Frontend::NodeKind::RespondsTo
            visit_responds_to(node.as(Frontend::RespondsToNode))
          when Frontend::NodeKind::Path
            resolve_path(node_id, node.as(Frontend::PathNode))
          when Frontend::NodeKind::Generic
            visit_generic(node.as(Frontend::GenericNode))
          when Frontend::NodeKind::Typeof
            visit_typeof(node.as(Frontend::TypeofNode))
          when Frontend::NodeKind::Include
            include_node = node.as(Frontend::IncludeNode)
            visit(include_node.target) if include_node.target && !include_node.target.invalid?
          when Frontend::NodeKind::Extend
            extend_node = node.as(Frontend::ExtendNode)
            visit(extend_node.target) if extend_node.target && !extend_node.target.invalid?
          else
            # Other kinds currently unsupported; ignore
          end
        end

        private def skip_macro_call?(call : Frontend::CallNode) : Bool
          callee_id = call.callee
          callee_node = @arena[callee_id]

          name = case callee_node
                 when Frontend::IdentifierNode
                   intern_name(callee_node.name)
                 when Frontend::MemberAccessNode
                   intern_name(callee_node.member)
                 else
                   nil
                 end
          return false unless name

          if symbol = lookup_macro_for_call(call, name)
            if symbol.is_a?(MacroSymbol)
              @identifier_symbols[callee_id] = symbol
              return true
            end
          end

          false
        end

        private def lookup_macro_for_call(call : Frontend::CallNode, name : String) : MacroSymbol?
          if symbol = lookup_macro_for_current_context(name)
            return symbol
          end

          receiver_owner = macro_receiver_owner(call)
          case receiver_owner
          when ClassSymbol
            lookup_macro_in_class_hierarchy(receiver_owner, name)
          when ModuleSymbol
            receiver_owner.scope.lookup_macro(name)
          else
            nil
          end
        end

        private def macro_receiver_owner(call : Frontend::CallNode) : Symbol?
          callee_node = @arena[call.callee]
          return nil unless callee_node.is_a?(Frontend::MemberAccessNode)

          resolve_symbol_in_current_context(callee_node.object)
        end

        private def resolve_symbol_in_current_context(expr_id : ExprId) : Symbol?
          node = @arena[expr_id]

          case node
          when Frontend::IdentifierNode
            name = intern_name(node.name)
            @current_table.lookup(name) || @root_table.lookup(name)
          when Frontend::PathNode
            segments = collect_path_segments(node)
            resolve_path_in_tables(@current_table, segments) || resolve_path_in_tables(@root_table, segments)
          when Frontend::GenericNode
            resolve_symbol_in_current_context(node.base_type)
          else
            nil
          end
        end

        private def resolve_identifier(node_id : ExprId, node : Frontend::IdentifierNode)
          slice = node.name
          return unless slice
          name = intern_name(slice)

          if name == "self"
            resolve_self(node_id)
            return
          end

          debug("[NameResolver] resolve #{name} in table=#{@current_table.object_id}")
          if constant_like_name?(name) && (symbol = lookup_constant_like_identifier(name))
            debug("[NameResolver] matched constant-like #{name} -> #{symbol.class}")
            @identifier_symbols[node_id] = symbol
          elsif symbol = @current_table.lookup(name)
            debug("[NameResolver] matched #{name} -> #{symbol.class}")
            @identifier_symbols[node_id] = symbol
          elsif constant_like_name?(name) && (symbol = lookup_lexical_constant(name))
            debug("[NameResolver] matched lexical constant #{name} -> #{symbol.class}")
            @identifier_symbols[node_id] = symbol
          elsif symbol = lookup_class_body_meta_symbol(name)
            debug("[NameResolver] matched class body meta #{name} -> #{symbol.class}")
            @identifier_symbols[node_id] = symbol
          elsif symbol = lookup_implicit_self_symbol(name)
            debug("[NameResolver] matched implicit self #{name} -> #{symbol.class}")
            @identifier_symbols[node_id] = symbol
          elsif macro_symbol = lookup_macro_for_current_context(name)
            if macro_symbol.is_a?(MacroSymbol)
              debug("[NameResolver] matched macro #{name}")
              @identifier_symbols[node_id] = macro_symbol
            else
              if type_expression_context? && type_expression_identifier_name?(name)
                return
              end
              if special_symbol = resolve_special_identifier(node_id, name)
                @identifier_symbols[node_id] = special_symbol
              else
                return if suppress_unresolved_callee_diagnostic?(name, node_id)
                trace_resolution_miss(name, node_id)
                debug("[NameResolver] unresolved #{name}")
                @diagnostics << Diagnostic.new("undefined local variable or method '#{name}'", node.span, node_id)
              end
            end
          else
            if type_expression_context? && type_expression_identifier_name?(name)
              return
            end
            # Report undefined identifiers in all scopes, not just top-level
            if special_symbol = resolve_special_identifier(node_id, name)
              @identifier_symbols[node_id] = special_symbol
            else
              return if suppress_unresolved_callee_diagnostic?(name, node_id)
              trace_resolution_miss(name, node_id)
              debug("[NameResolver] unresolved #{name}")
              @diagnostics << Diagnostic.new("undefined local variable or method '#{name}'", node.span, node_id)
            end
          end
        end

        private def lookup_constant_like_identifier(name : String) : Symbol?
          return nil if name.starts_with?("__")
          lookup_lexical_constant(name) || @root_table.lookup(name)
        end

        private def visit_generic(node : Frontend::GenericNode)
          visit_type_expression(node.base_type)
          node.type_args.each do |arg_id|
            visit_type_expression(arg_id)
          end
        end

        private def visit_typeof(node : Frontend::TypeofNode)
          node.args.each do |arg_id|
            visit(arg_id)
          end
        end

        private def visit_type_expression(node_id : ExprId)
          @type_expression_depth += 1
          visit(node_id)
        ensure
          @type_expression_depth -= 1 if @type_expression_depth > 0
        end

        private def type_expression_context? : Bool
          @type_expression_depth > 0
        end

        private def type_expression_identifier_name?(name : String) : Bool
          return true if constant_like_name?(name)
          return true if brace_type_expression_identifier_name?(name)

          stripped = if name.starts_with?("**")
                       name[2..]
                     elsif name.starts_with?("*")
                       name[1..]
                     else
                       nil
                     end

          stripped ? constant_like_name?(stripped) : false
        end

        private def brace_type_expression_identifier_name?(name : String) : Bool
          name.starts_with?('{') && name.ends_with?('}')
        end

        private def type_application_call?(call : Frontend::CallNode) : Bool
          return false if call.block
          return false if call.named_args

          callee_node = @arena[call.callee]
          case callee_node
          when Frontend::PathNode
            segments = collect_path_segments(callee_node)
            return false if segments.empty?
            symbol = resolve_path_in_tables(@current_table, segments) || resolve_path_in_tables(@root_table, segments)
            symbol.is_a?(ClassSymbol) || symbol.is_a?(ModuleSymbol) || symbol.is_a?(EnumSymbol) || symbol.is_a?(AliasSymbol)
          when Frontend::IdentifierNode
            constant_like_name?(intern_name(callee_node.name))
          else
            false
          end
        end

        private def visit_type_application_call(call : Frontend::CallNode)
          visit_type_expression(call.callee)
          call.args.each do |arg_id|
            visit_type_expression(arg_id)
          end
        end

        private def call_type_expression_arg?(call : Frontend::CallNode, index : Int32) : Bool
          return false unless index == 0

          callee_node = @arena[call.callee]
          case callee_node
          when Frontend::IdentifierNode
            intern_name(callee_node.name) == "unsafe_as"
          when Frontend::MemberAccessNode
            intern_name(callee_node.member) == "unsafe_as"
          else
            false
          end
        end

        private def resolve_instance_var(node_id : ExprId, node : Frontend::InstanceVarNode)
          slice = node.name
          return unless slice
          name = intern_name(slice)
          if symbol = @current_table.lookup(name)
            @identifier_symbols[node_id] = symbol
          end
        end

        private def resolve_class_var(node_id : ExprId, node : Frontend::ClassVarNode)
          slice = node.name
          return unless slice
          name = intern_name(slice)
          if symbol = @current_table.lookup(name)
            @identifier_symbols[node_id] = symbol
          end
        end

        private def resolve_global_var(node_id : ExprId, node : Frontend::GlobalNode)
          slice = node.name
          return unless slice
          name = intern_name(slice)
          if symbol = @root_table.lookup(name)
            @identifier_symbols[node_id] = symbol
          end
        end

        # Handle assignment target - creates a new local variable if it's an identifier
        private def handle_assign_target(target_id : ExprId)
          return if target_id.invalid?
          target_node = @arena[target_id]

          # Only handle simple identifier targets (not instance vars, etc.)
          if target_node.is_a?(Frontend::IdentifierNode)
            slice = target_node.name
            return unless slice
            name = intern_name(slice)

            # Check if variable already exists (reassignment vs first assignment)
            if existing = @current_table.lookup_local(name)
              # Reassignment: reuse existing symbol, update identifier mapping
              @identifier_symbols[target_id] = existing
            else
              # First assignment: create new symbol
              symbol = VariableSymbol.new(name, target_id)
              @current_table.define(name, symbol)
              @identifier_symbols[target_id] = symbol
            end
          elsif target_node.is_a?(Frontend::MultipleAssignNode)
            target_node.targets.each do |nested_target|
              handle_assign_target(nested_target)
            end
          elsif target_node.is_a?(Frontend::SplatNode)
            handle_assign_target(target_node.expr)
          else
            # For other assignment targets (instance vars, indexed access, etc.), just visit them
            visit(target_id)
          end
        end

        private def visit_macro_literal(node : Frontend::MacroLiteralNode)
          # The compile shadow path resolves generated roots after macro
          # expansion. Visiting source macro DSL expressions here mostly creates
          # noise for built-ins like flag?, skip_file and __FILE__.
        end

        private def visit_type_declaration(node : Frontend::TypeDeclarationNode)
          if value = node.value
            visit(value) unless value.invalid?
          end

          name = intern_name(node.name)
          declared_type = intern_name(node.declared_type)

          unless @current_table.lookup_local(name)
            @current_table.define(name, VariableSymbol.new(name, BLOCK_SYMBOL_NODE_ID, declared_type: declared_type))
          end
        end

        private def visit_out(node_id : ExprId, node : Frontend::OutNode)
          name = intern_name(node.identifier)

          if existing = @current_table.lookup_local(name)
            @identifier_symbols[node_id] = existing
          else
            symbol = VariableSymbol.new(name, node_id)
            @current_table.define(name, symbol)
            @identifier_symbols[node_id] = symbol
          end
        end

        private def visit_def(node_id : ExprId, node : Frontend::DefNode)
          visit_def_in_lookup_scope(node_id, node, @current_table)
        end

        private def visit_def_in_lookup_scope(
          node_id : ExprId,
          node : Frontend::DefNode,
          lookup_table : SymbolTable
        )
          name_slice = node.name
          return unless name_slice

          name = intern_name(name_slice)
          symbol = lookup_table.lookup(name)

          method_symbol = case symbol
          when MethodSymbol
            symbol
          when OverloadSetSymbol
            symbol.overloads.find { |overload| overload.node_id == node_id } || symbol.overloads.last?
          else
            nil
          end

          return unless method_symbol

          method_scope = method_symbol.scope
          @identifier_symbols[node_id] = method_symbol
          prev_table = @current_table
          @current_method_is_class_method_stack << method_symbol.is_class_method?
          @current_table = method_scope

          visit_expression_list(node.body || [] of ExprId)

          @current_method_is_class_method_stack.pop
          @current_table = prev_table
        end

        private def visit_class(node_id : ExprId, node : Frontend::ClassNode)
          name_slice = node.name
          return unless name_slice

          name = intern_name(name_slice)
          symbol = @current_table.lookup(name)
          unless symbol.is_a?(ClassSymbol)
            return
          end

          class_scope = symbol.scope
          prev_table = @current_table
          @current_table = class_scope
          @namespace_stack << symbol

          (node.body || [] of ExprId).each do |expr_id|
            body_node = @arena[expr_id]
            if body_node.is_a?(Frontend::DefNode) && def_receiver_self?(body_node)
              visit_def_in_lookup_scope(expr_id, body_node, symbol.class_scope)
            else
              with_class_body_meta_lookup(symbol.class_scope) do
                visit(expr_id)
              end
            end
          end

          @namespace_stack.pop
          @current_table = prev_table
        end

        private def visit_module(node_id : ExprId, node : Frontend::ModuleNode)
          name_slice = node.name
          return unless name_slice

          name = intern_name(name_slice)
          symbol = @current_table.lookup(name)
          case symbol
          when ModuleSymbol
            @identifier_symbols[node_id] = symbol

            prev_table = @current_table
            @current_table = symbol.scope
            @namespace_stack << symbol
            (node.body || [] of ExprId).each { |expr_id| visit(expr_id) }
            @namespace_stack.pop
            @current_table = prev_table
          when ClassSymbol
            @identifier_symbols[node_id] = symbol

            prev_table = @current_table
            @current_table = symbol.scope
            @namespace_stack << symbol
            (node.body || [] of ExprId).each { |expr_id| visit(expr_id) }
            @namespace_stack.pop
            @current_table = prev_table
          else
            return
          end
        end

        private def visit_enum(node_id : ExprId, node : Frontend::EnumNode)
          name_slice = node.name
          return unless name_slice

          name = intern_name(name_slice)
          symbol = @current_table.lookup(name)
          unless symbol.is_a?(EnumSymbol)
            return
          end

          @identifier_symbols[node_id] = symbol

          prev_table = @current_table
          @current_table = symbol.scope
          @namespace_stack << symbol
          node.members.each do |member|
            if value = member.value
              visit(value)
            end
          end
          (node.body || [] of ExprId).each { |expr_id| visit(expr_id) }
          @namespace_stack.pop
          @current_table = prev_table
        end

        # Control flow node visitors

        private def visit_case(node : Frontend::CaseNode)
          if value = node.value
            visit(value)
          end

          node.when_branches.each do |branch|
            branch.conditions.each { |expr_id| visit(expr_id) }
            visit_expression_list(branch.body)
          end

          node.in_branches.try &.each do |branch|
            branch.conditions.each { |expr_id| visit(expr_id) }
            visit_expression_list(branch.body)
          end

          node.else_branch.try { |body| visit_expression_list(body) }
        end

        private def visit_if(node : Frontend::IfNode)
          return if skip_macro_directive?(node.then_body)

          # Visit condition
          visit(node.condition)
          # Visit then body
          visit_expression_list(node.then_body)
          # Visit elsif branches
          node.elsifs.try &.each do |elsif_branch|
            visit(elsif_branch.condition)
            visit_expression_list(elsif_branch.body)
          end
          # Visit else body
          node.else_body.try { |body| visit_expression_list(body) }
        end

        private def visit_unless(node : Frontend::UnlessNode)
          return if skip_macro_directive?(node.then_branch)

          # Visit condition
          visit(node.condition)
          # Visit then branch
          visit_expression_list(node.then_branch)
          # Visit else branch
          node.else_branch.try { |body| visit_expression_list(body) }
        end

        private def visit_while(node : Frontend::WhileNode)
          # Visit condition
          visit(node.condition)
          # Visit body
          visit_expression_list(node.body)
        end

        private def visit_until(node : Frontend::UntilNode)
          # Visit condition
          visit(node.condition)
          # Visit body
          visit_expression_list(node.body)
        end

        private def visit_loop(node : Frontend::LoopNode)
          visit_expression_list(node.body)
        end

        private def visit_begin(node : Frontend::BeginNode)
          visit_expression_list(node.body)

          node.rescue_clauses.try &.each do |clause|
            prev_table = @current_table
            rescue_scope = SymbolTable.new(prev_table)
            @current_table = rescue_scope

            if variable_name = clause.variable_name
              name = intern_name(variable_name)
              rescue_scope.define(name, VariableSymbol.new(name, BLOCK_SYMBOL_NODE_ID)) unless rescue_scope.lookup_local(name)
            end

            visit_expression_list(clause.body)
            @current_table = prev_table
          end

          node.else_body.try { |body| visit_expression_list(body) }
          node.ensure_body.try { |body| visit_expression_list(body) }
        end

        private def visit_string_interpolation(node : Frontend::StringInterpolationNode)
          node.pieces.each do |piece|
            next unless piece.kind == Frontend::StringPiece::Kind::Expression
            next unless expr = piece.expr

            visit(expr)
          end
        end

        private def visit_raise(node : Frontend::RaiseNode)
          if value = node.value
            visit(value)
          end
        end

        private def visit_yield(node : Frontend::YieldNode)
          node.args.try &.each { |arg_id| visit(arg_id) }
        end

        private def visit_is_a(node : Frontend::IsANode)
          visit(node.expression)
        end

        private def visit_responds_to(node : Frontend::RespondsToNode)
          visit(node.expression)
          visit(node.method_name)
        end

        private def visit_block(node : Frontend::BlockNode)
          prev_table = @current_table
          block_scope = SymbolTable.new(prev_table)
          @current_table = block_scope

          node.params.try do |params|
            params.each do |param|
              if default = param.default_value
                visit(default)
              end

              next unless param_name = param.name
              name = intern_name(param_name)
              declared_type = param.type_annotation.try { |ann| intern_name(ann) }

              debug("[NameResolver] define block param #{name}")
              unless block_scope.lookup_local(name)
                block_scope.define(name, VariableSymbol.new(name, BLOCK_SYMBOL_NODE_ID, declared_type: declared_type))
              end
            end
          end

          visit_expression_list(node.body)

          @current_table = prev_table
        end

        private def visit_proc_literal(node : Frontend::ProcLiteralNode)
          prev_table = @current_table
          proc_scope = SymbolTable.new(prev_table)
          @current_table = proc_scope

          node.params.try do |params|
            params.each do |param|
              if default = param.default_value
                visit(default)
              end

              next unless param_name = param.name
              name = intern_name(param_name)
              declared_type = param.type_annotation.try { |ann| intern_name(ann) }

              debug("[NameResolver] define proc param #{name}")
              unless proc_scope.lookup_local(name)
                proc_scope.define(name, VariableSymbol.new(name, BLOCK_SYMBOL_NODE_ID, declared_type: declared_type))
              end
            end
          end

        node.body.each { |expr_id| visit(expr_id) }

        @current_table = prev_table
      end

        private def resolve_path(node_id : ExprId, node : Frontend::PathNode)
          segments = collect_path_segments(node)
          return if segments.empty?

          symbol =
            if absolute_path?(node)
              resolve_path_in_tables(@root_table, segments)
            else
              resolve_path_in_tables(@current_table, segments) || resolve_path_in_tables(@root_table, segments)
            end
          if symbol
            @identifier_symbols[node_id] = symbol
          elsif top_level_scope?
            @diagnostics << Diagnostic.new("uninitialized constant #{segments.join("::")}", node.span, node_id)
          end
        end

      private def absolute_path?(node : Frontend::PathNode) : Bool
        if left_id = node.left
          left = @arena[left_id]
          left.is_a?(Frontend::PathNode) && absolute_path?(left)
        else
          true
        end
      end

      private def collect_path_segments(node : Frontend::PathNode) : Array(String)
        result = [] of String
        if left_id = node.left
          unless left_id.invalid?
            case left = @arena[left_id]
            when Frontend::PathNode
              collect_path_segments(left).each { |entry| result << entry }
            when Frontend::IdentifierNode
              if slice = left.name
                result << intern_name(slice)
              end
            when Frontend::ConstantNode
              if slice = left.name
                result << intern_name(slice)
              end
            end
          end
        end

        right = @arena[node.right]
        case right
        when Frontend::PathNode
          collect_path_segments(right).each { |entry| result << entry }
        when Frontend::IdentifierNode
          if slice = right.name
            result << intern_name(slice)
          end
        when Frontend::ConstantNode
          if slice = right.name
            result << intern_name(slice)
          end
        end

        result
      end

      private def resolve_path_in_tables(table : SymbolTable, segments : Array(String)) : Symbol?
        return nil if segments.empty?
        first, *rest = segments
        current = table.lookup(first)
        return current if rest.empty?

        rest.each do |segment|
          scope = scope_for(current)
          return nil unless scope
          current = scope.lookup(segment)
          return nil unless current
        end

        current
      end

        private def scope_for(symbol : Symbol?) : SymbolTable?
          case symbol
          when ClassSymbol
            symbol.scope
          when ModuleSymbol
            symbol.scope
          else
            nil
          end
        end

        private def def_receiver_self?(node : Frontend::DefNode) : Bool
          receiver = node.receiver
          return false unless receiver
          intern_name(receiver) == "self"
        end

        private def top_level_scope? : Bool
          @current_table.same?(@root_table)
        end

        private def constant_like_name?(name : String) : Bool
          return false if name.empty?
          first = name.byte_at(0)
          (first >= 'A'.ord.to_u8 && first <= 'Z'.ord.to_u8) || name.starts_with?("__")
        end

        private def resolve_special_identifier(node_id : ExprId, name : String) : VariableSymbol?
          case name
          when "__FILE__", "__DIR__"
            VariableSymbol.new(name, node_id, declared_type: "String")
          when "__LINE__"
            VariableSymbol.new(name, node_id, declared_type: "Int32")
          when "ARGC_UNSAFE"
            VariableSymbol.new(name, node_id, declared_type: "Int32")
          when "ARGV_UNSAFE"
            VariableSymbol.new(name, node_id, declared_type: "Pointer(Pointer(UInt8))")
          else
            nil
          end
        end

        private def visit_proc_pointer(node : Frontend::UnaryNode) : Nil
          operand_id = node.operand
          return if operand_id.invalid?

          operand = @arena[operand_id]
          case operand
          when Frontend::CallNode
            if callee_id = operand.callee
              @call_callee_depth += 1
              begin
                visit(callee_id)
              ensure
                @call_callee_depth -= 1
              end
            end
          else
            visit(operand_id)
          end
        end

        private def lookup_lexical_constant(name : String) : Symbol?
          @namespace_stack.reverse_each do |symbol|
            case symbol
            when ClassSymbol
              if resolved = symbol.scope.lookup_local(name)
                return resolved
              end
              if resolved = symbol.class_scope.lookup_local(name)
                return resolved
              end
            when ModuleSymbol
              if resolved = symbol.scope.lookup_local(name)
                return resolved
              end
            when EnumSymbol
              if resolved = symbol.scope.lookup_local(name)
                return resolved
              end
            end
          end
          nil
        end

        private def resolved_enum_symbol(expr_id : ExprId) : EnumSymbol?
          return nil if expr_id.invalid?
          resolve_enum_symbol(@identifier_symbols[expr_id]?)
        end

        private def with_enum_index_scope(enum_symbol : EnumSymbol, &)
          @namespace_stack << enum_symbol
          yield
        ensure
          @namespace_stack.pop
        end

        private def resolve_enum_symbol(symbol : Symbol?) : EnumSymbol?
          case symbol
          when EnumSymbol
            symbol
          when AliasSymbol
            resolve_enum_symbol(resolve_symbol_in_current_context(symbol.target))
          else
            nil
          end
        end

        private def resolve_symbol_in_current_context(name : String) : Symbol?
          if name.includes?("::")
            segments = name.split("::").reject(&.empty?)
            return nil if segments.empty?
            return resolve_path_in_tables(@current_table, segments) || resolve_path_in_tables(@root_table, segments)
          end

          @current_table.lookup(name) || @root_table.lookup(name)
        end

        private def lookup_class_body_meta_symbol(name : String) : Symbol?
          @class_body_meta_lookup_stack.reverse_each do |table|
            if resolved = table.lookup(name)
              return resolved
            end
          end
          nil
        end

        private def with_class_body_meta_lookup(table : SymbolTable, &)
          @class_body_meta_lookup_stack << table
          yield
        ensure
          @class_body_meta_lookup_stack.pop
        end

        private def resolve_self(node_id : ExprId)
          if owner = current_owner_symbol
            @identifier_symbols[node_id] = owner
          end
        end

        private def current_owner_symbol : Symbol?
          @namespace_stack.last?
        end

        private def current_method_is_class_method? : Bool
          @current_method_is_class_method_stack.last? || false
        end

        private def in_method_body? : Bool
          !@current_method_is_class_method_stack.empty?
        end

        private def suppress_unresolved_callee_diagnostic?(name : String, node_id : ExprId) : Bool
          return false unless in_method_body?
          return false if name.empty? || constant_like_name?(name)
          return true if @call_callee_depth > 0

          @bare_statement_candidate_stack.includes?(node_id)
        end

        private def visit_expression_list(expressions : Array(ExprId)) : Nil
          expressions.each do |expr_id|
            visit_expression_statement(expr_id)
          end
        end

        private def visit_expression_statement(expr_id : ExprId) : Nil
          push_bare_statement_candidate(expr_id)
          visit(expr_id)
        ensure
          pop_bare_statement_candidate(expr_id)
        end

        private def push_bare_statement_candidate(expr_id : ExprId) : Nil
          return unless in_method_body?
          return if expr_id.invalid?
          return unless @arena[expr_id].is_a?(Frontend::IdentifierNode)

          @bare_statement_candidate_stack << expr_id
        end

        private def pop_bare_statement_candidate(expr_id : ExprId) : Nil
          return if @bare_statement_candidate_stack.empty?
          return unless @bare_statement_candidate_stack.last? == expr_id

          @bare_statement_candidate_stack.pop
        end

        private def lookup_implicit_self_symbol(name : String) : Symbol?
          owner = current_owner_symbol
          return nil unless owner

          case owner
          when ClassSymbol
            if symbol = lookup_in_class_hierarchy(owner, name, class_methods: current_method_is_class_method?)
              return symbol
            end
          when ModuleSymbol
            if symbol = owner.scope.lookup(name)
              return symbol
            end
            if symbol = lookup_in_module_includers(owner, name)
              return symbol
            end
          when EnumSymbol
            if symbol = owner.scope.lookup(name)
              return symbol
            end
          end

          nil
        end

        private def lookup_macro_for_current_context(name : String) : MacroSymbol?
          if symbol = @current_table.lookup_macro(name)
            return symbol
          end

          owner = current_owner_symbol
          return nil unless owner.is_a?(ClassSymbol)

          lookup_macro_in_class_hierarchy(owner, name)
        end

        private def lookup_macro_in_class_hierarchy(
          class_symbol : ClassSymbol,
          name : String,
          visited = Set(ClassSymbol).new
        ) : MacroSymbol?
          return nil unless visited.add?(class_symbol)

          if symbol = class_symbol.scope.lookup_macro(name)
            return symbol
          end

          superclass_name = class_symbol.superclass_name
          return nil unless superclass_name

          superclass_symbol = lookup_root_symbol_by_name(superclass_name)
          return nil unless superclass_symbol.is_a?(ClassSymbol)

          lookup_macro_in_class_hierarchy(superclass_symbol, name, visited: visited)
        end

        private def lookup_in_class_hierarchy(
          class_symbol : ClassSymbol,
          name : String,
          *,
          class_methods : Bool,
          visited = Set(ClassSymbol).new
        ) : Symbol?
          return nil unless visited.add?(class_symbol)

          scope = class_methods ? class_symbol.class_scope : class_symbol.scope
          if symbol = scope.lookup(name)
            return symbol
          end

          superclass_name = class_symbol.superclass_name
          return nil unless superclass_name

          superclass_symbol = lookup_root_symbol_by_name(superclass_name)
          return nil unless superclass_symbol.is_a?(ClassSymbol)

          lookup_in_class_hierarchy(superclass_symbol, name, class_methods: class_methods, visited: visited)
        end

        private def lookup_root_symbol_by_name(name : String) : Symbol?
          if name.includes?("::")
            segments = name.split("::").reject(&.empty?)
            return nil if segments.empty?
            resolve_path_in_tables(@root_table, segments)
          else
            @root_table.lookup(name)
          end
        end

        private def lookup_in_module_includers(module_symbol : ModuleSymbol, name : String) : Symbol?
          module_symbol.instance_includers.each do |includer|
            case includer
            when ClassSymbol
              if symbol = lookup_in_class_hierarchy(includer, name, class_methods: false)
                return symbol
              end
            when ModuleSymbol
              if symbol = includer.scope.lookup(name)
                return symbol
              end
            end
          end

          nil
        end

        private def skip_macro_directive?(body : Array(ExprId)) : Bool
          return false unless body.size == 1
          node = @arena[body.first]
          return false unless node.is_a?(Frontend::IdentifierNode)
          return false unless slice = node.name
          intern_name(slice) == "skip_file"
        end

      private def debug(message : String)
        return unless ENV.has_key?("LSP_DEBUG_BLOCK")
        STDOUT.puts(message)
      end

      private def trace_resolution_miss(name : String, node_id : ExprId) : Nil
        filter = ENV["DEBUG_RESOLUTION_MISS_NAMES"]?
        return unless filter

        names = filter.split(',').map(&.strip).reject(&.empty?)
        return unless names.includes?(name)

        owner = current_owner_symbol
        owner_desc = case owner
                     when ClassSymbol
                       "ClassSymbol(#{owner.name})"
                     when ModuleSymbol
                       "ModuleSymbol(#{owner.name})"
                     when EnumSymbol
                       "EnumSymbol(#{owner.name})"
                     else
                       "nil"
                     end

        owner_scope_symbol = case owner
                             when ClassSymbol
                               owner.scope.lookup(name)
                             when ModuleSymbol
                               owner.scope.lookup(name)
                             when EnumSymbol
                               owner.scope.lookup(name)
                             else
                               nil
                             end
        owner_scope_macro = case owner
                            when ClassSymbol
                              owner.scope.lookup_macro(name)
                            when ModuleSymbol
                              owner.scope.lookup_macro(name)
                            when EnumSymbol
                              owner.scope.lookup_macro(name)
                            else
                              nil
                            end
        owner_class_scope_macro = owner.is_a?(ClassSymbol) ? owner.class_scope.lookup_macro(name) : nil
        superclass_name = owner.is_a?(ClassSymbol) ? owner.superclass_name : nil
        superclass_symbol = if owner.is_a?(ClassSymbol) && (super_name = owner.superclass_name)
                              lookup_root_symbol_by_name(super_name)
                            end
        superclass_macro = superclass_symbol.as?(ClassSymbol).try(&.scope.lookup_macro(name))
        superclass_super = superclass_symbol.is_a?(ClassSymbol) ? superclass_symbol.superclass_name : nil
        object_symbol = lookup_root_symbol_by_name("Object")
        object_macro = object_symbol.as?(ClassSymbol).try(&.scope.lookup_macro(name))
        object_class_scope_macro = object_symbol.as?(ClassSymbol).try(&.class_scope.lookup_macro(name))

        lexical_constant = constant_like_name?(name) ? lookup_lexical_constant(name) : nil
        root_symbol = @root_table.lookup(name)
        root_macro = @root_table.lookup_macro(name)
        span = @arena[node_id].span
        STDERR.puts "[RESOLVE_MISS] name=#{name} owner=#{owner_desc} superclass=#{superclass_name} superclass_symbol=#{superclass_symbol.class.name if superclass_symbol} superclass_super=#{superclass_super} current_local=#{@current_table.lookup_local(name).class.name if @current_table.lookup_local(name)} current_lookup=#{@current_table.lookup(name).class.name if @current_table.lookup(name)} current_macro=#{@current_table.lookup_macro(name).class.name if @current_table.lookup_macro(name)} owner_scope=#{owner_scope_symbol.class.name if owner_scope_symbol} owner_scope_macro=#{owner_scope_macro.class.name if owner_scope_macro} owner_class_scope_macro=#{owner_class_scope_macro.class.name if owner_class_scope_macro} superclass_macro=#{superclass_macro.class.name if superclass_macro} object_symbol=#{object_symbol.class.name if object_symbol} object_macro=#{object_macro.class.name if object_macro} object_class_scope_macro=#{object_class_scope_macro.class.name if object_class_scope_macro} lexical_constant=#{lexical_constant.class.name if lexical_constant} root=#{root_symbol.class.name if root_symbol} root_macro=#{root_macro.class.name if root_macro} span=#{span.start_line}:#{span.start_column}"
      end

      private def intern_name(slice : Slice(UInt8)) : String
        @string_pool.intern_string(slice)
      end
    end
    end
  end
end
