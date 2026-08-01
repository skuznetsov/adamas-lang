# NodeDispatch: Dispatch table for TypedNode operations
# Eliminates pattern matching IR explosion by using O(1) table lookup
#
# Problem: Pattern matching on 94-type union + block inlining at yields
#          generates 300K+ lines of LLVM IR for single functions.
#
# Solution: Use NodeKind enum for O(1) dispatch without pattern matching.
#           NodeKind is already defined for each node type.

module Adamas
  module Compiler
    module Frontend
      # Dispatch table for extracting child expressions from nodes.
      # Uses NodeKind enum for O(1) switch instead of 94-type pattern matching.
      module NodeDispatch
        # Main dispatch function: get child expressions from any node
        # Uses NodeKind enum switch instead of pattern matching on TypedNode union
        @[NoInline]
        def self.get_child_exprs(arena : ArenaLike, expr_id : ExprId) : Array(ExprId)
          node = arena[expr_id]
          kind = Frontend.node_kind(node)

          # Use NodeKind enum for dispatch - this generates a simple jump table
          # instead of cascading type checks for 94 types
          case kind
          when NodeKind::Assign
            n = node.as(AssignNode)
            [n.target, n.value]

          when NodeKind::Binary
            n = node.as(BinaryNode)
            [n.left, n.right]

          when NodeKind::Unary
            case node
            when UnaryNode
              [node.operand]
            when SplatNode
              [node.expr]
            else
              [] of ExprId
            end

          when NodeKind::Ternary
            n = node.as(TernaryNode)
            [n.condition, n.true_branch, n.false_branch]

          when NodeKind::MemberAccess
            n = node.as(MemberAccessNode)
            [n.object]

          when NodeKind::SafeNavigation
            n = node.as(SafeNavigationNode)
            [n.object]

          when NodeKind::Index
            n = node.as(IndexNode)
            children = [n.object] of ExprId
            n.indexes.each { |idx| children << idx }
            children

          when NodeKind::Range
            n = node.as(RangeNode)
            [n.begin_expr, n.end_expr]

          when NodeKind::Call
            n = node.as(CallNode)
            children = [] of ExprId
            children << n.callee unless n.callee.invalid?
            n.args.each { |arg| children << arg }
            if named_args = n.named_args
              named_args.each { |arg| children << arg.value }
            end
            if block_expr = n.block
              children << block_expr unless block_expr.invalid?
            end
            children

          when NodeKind::Block
            n = node.as(BlockNode)
            children = [] of ExprId
            append_parameter_defaults(children, n.params)
            n.body.each { |expr| children << expr }
            children

          when NodeKind::ProcLiteral
            n = node.as(ProcLiteralNode)
            children = [] of ExprId
            append_parameter_defaults(children, n.params)
            n.body.each { |expr| children << expr }
            children

          when NodeKind::If
            n = node.as(IfNode)
            children = [n.condition] of ExprId
            n.then_body.each { |expr| children << expr }
            if elsifs = n.elsifs
              elsifs.each do |branch|
                children << branch.condition
                branch.body.each { |expr| children << expr }
              end
            end
            if else_body = n.else_body
              else_body.each { |expr| children << expr }
            end
            children

          when NodeKind::Unless
            n = node.as(UnlessNode)
            children = [n.condition] of ExprId
            n.then_branch.each { |expr| children << expr }
            if else_branch = n.else_branch
              else_branch.each { |expr| children << expr }
            end
            children

          when NodeKind::While
            n = node.as(WhileNode)
            children = [n.condition] of ExprId
            n.body.each { |expr| children << expr }
            children

          when NodeKind::Until
            n = node.as(UntilNode)
            children = [n.condition] of ExprId
            n.body.each { |expr| children << expr }
            children

          when NodeKind::For
            n = node.as(ForNode)
            children = [n.collection] of ExprId
            n.body.each { |expr| children << expr }
            children

          when NodeKind::Loop
            n = node.as(LoopNode)
            n.body.to_a

          when NodeKind::Case
            n = node.as(CaseNode)
            children = [] of ExprId
            if value = n.value
              children << value unless value.invalid?
            end
            n.when_branches.each do |branch|
              branch.conditions.each { |cond| children << cond }
              branch.body.each { |expr| children << expr }
            end
            if in_branches = n.in_branches
              in_branches.each do |branch|
                branch.conditions.each { |cond| children << cond }
                branch.body.each { |expr| children << expr }
              end
            end
            if else_branch = n.else_branch
              else_branch.each { |expr| children << expr }
            end
            children

          when NodeKind::Select
            n = node.as(SelectNode)
            children = [] of ExprId
            n.branches.each do |branch|
              children << branch.condition unless branch.condition.invalid?
              branch.body.each { |expr| children << expr }
            end
            if else_body = n.else_branch
              else_body.each { |expr| children << expr }
            end
            children

          when NodeKind::Include
            n = node.as(IncludeNode)
            n.target.invalid? ? [] of ExprId : [n.target]

          when NodeKind::Extend
            n = node.as(ExtendNode)
            n.target.invalid? ? [] of ExprId : [n.target]

          when NodeKind::Return
            n = node.as(ReturnNode)
            if value = n.value
              value.invalid? ? [] of ExprId : [value]
            else
              [] of ExprId
            end

          when NodeKind::Break
            n = node.as(BreakNode)
            if value = n.value
              value.invalid? ? [] of ExprId : [value]
            else
              [] of ExprId
            end

          when NodeKind::Next
            n = node.as(NextNode)
            if value = n.value
              value.invalid? ? [] of ExprId : [value]
            else
              [] of ExprId
            end

          when NodeKind::Yield
            n = node.as(YieldNode)
            if args = n.args
              args.to_a
            else
              [] of ExprId
            end

          when NodeKind::Spawn
            n = node.as(SpawnNode)
            children = [] of ExprId
            if expr = n.expression
              children << expr unless expr.invalid?
            end
            if body = n.body
              body.each { |expr| children << expr }
            end
            children

          when NodeKind::Grouping
            n = node.as(GroupingNode)
            [n.expression]

          when NodeKind::ArrayLiteral
            n = node.as(ArrayLiteralNode)
            children = [] of ExprId
            if custom_name = n.custom_name
              children << custom_name unless custom_name.invalid?
            end
            n.elements.each { |elem| children << elem }
            if of_type = n.of_type
              children << of_type unless of_type.invalid?
            end
            children

          when NodeKind::TupleLiteral
            n = node.as(TupleLiteralNode)
            n.elements.to_a

          when NodeKind::NamedTupleLiteral
            n = node.as(NamedTupleLiteralNode)
            n.entries.map(&.value)

          when NodeKind::HashLiteral
            n = node.as(HashLiteralNode)
            children = [] of ExprId
            if custom_name = n.custom_name
              children << custom_name unless custom_name.invalid?
            end
            n.entries.each do |entry|
              children << entry.key
              children << entry.value
            end
            children

          when NodeKind::StringInterpolation
            n = node.as(StringInterpolationNode)
            children = [] of ExprId
            n.pieces.each do |piece|
              if expr = piece.expr
                children << expr unless expr.invalid?
              end
            end
            children

          when NodeKind::Begin
            n = node.as(BeginNode)
            children = [] of ExprId
            n.body.each { |expr| children << expr }
            if rescues = n.rescue_clauses
              rescues.each do |clause|
                clause.body.each { |expr| children << expr }
              end
            end
            if else_body = n.else_body
              else_body.each { |expr| children << expr }
            end
            if ensure_body = n.ensure_body
              ensure_body.each { |expr| children << expr }
            end
            children

          when NodeKind::Constant
            n = node.as(ConstantNode)
            n.value.invalid? ? [] of ExprId : [n.value]

          when NodeKind::Raise
            n = node.as(RaiseNode)
            if value = n.value
              value.invalid? ? [] of ExprId : [value]
            else
              [] of ExprId
            end

          when NodeKind::Require
            n = node.as(RequireNode)
            [n.path]

          when NodeKind::TypeDeclaration
            n = node.as(TypeDeclarationNode)
            if value = n.value
              value.invalid? ? [] of ExprId : [value]
            else
              [] of ExprId
            end

          when NodeKind::InstanceVarDecl
            n = node.as(InstanceVarDeclNode)
            if value = n.value
              value.invalid? ? [] of ExprId : [value]
            else
              [] of ExprId
            end

          when NodeKind::ClassVarDecl
            n = node.as(ClassVarDeclNode)
            if value = n.value
              value.invalid? ? [] of ExprId : [value]
            else
              [] of ExprId
            end

          when NodeKind::Def
            n = node.as(DefNode)
            children = [] of ExprId
            append_parameter_defaults(children, n.params)
            if body = n.body
              body.each { |expr| children << expr }
            end
            children

          when NodeKind::Class
            n = node.as(ClassNode)
            (n.body || [] of ExprId).to_a

          when NodeKind::Struct
            n = node.as(ClassNode)
            (n.body || [] of ExprId).to_a

          when NodeKind::Module
            n = node.as(ModuleNode)
            (n.body || [] of ExprId).to_a

          when NodeKind::Union
            n = node.as(UnionNode)
            (n.body || [] of ExprId).to_a

          when NodeKind::Enum
            n = node.as(EnumNode)
            children = [] of ExprId
            n.members.each do |member|
              if value = member.value
                children << value unless value.invalid?
              end
            end
            if body = n.body
              body.each { |expr_id| children << expr_id unless expr_id.invalid? }
            end
            children

          when NodeKind::Annotation
            n = node.as(AnnotationNode)
            children = [n.name] of ExprId
            n.args.each { |arg| children << arg }
            if named_args = n.named_args
              named_args.each { |arg| children << arg.value }
            end
            children

          when NodeKind::Getter
            n = node.as(GetterNode)
            children = [] of ExprId
            append_accessor_defaults(children, n.specs)
            children

          when NodeKind::Setter
            n = node.as(SetterNode)
            children = [] of ExprId
            append_accessor_defaults(children, n.specs)
            children

          when NodeKind::Property
            n = node.as(PropertyNode)
            children = [] of ExprId
            append_accessor_defaults(children, n.specs)
            children

          when NodeKind::MacroExpression
            n = node.as(MacroExpressionNode)
            [n.expression]

          when NodeKind::MacroIf
            n = node.as(MacroIfNode)
            children = [n.condition, n.then_body] of ExprId
            if else_body = n.else_body
              children << else_body
            end
            children

          when NodeKind::MacroFor
            n = node.as(MacroForNode)
            [n.iterable, n.body]

          when NodeKind::MacroLiteral
            n = node.as(MacroLiteralNode)
            children = [] of ExprId
            n.pieces.each do |piece|
              if expr = piece.expr
                children << expr unless expr.invalid?
              end
              if iterable = piece.iterable
                children << iterable unless iterable.invalid?
              end
            end
            children

          when NodeKind::MacroDef
            n = node.as(MacroDefNode)
            n.body.invalid? ? [] of ExprId : [n.body]

          when NodeKind::MultipleAssign
            n = node.as(MultipleAssignNode)
            children = [] of ExprId
            n.targets.each { |t| children << t }
            children << n.value
            children

          when NodeKind::VisibilityModifier
            n = node.as(VisibilityModifierNode)
            [n.expression]

          when NodeKind::Pointerof
            n = node.as(PointerofNode)
            n.args.to_a

          when NodeKind::Sizeof
            n = node.as(SizeofNode)
            n.args.to_a

          when NodeKind::Offsetof
            n = node.as(OffsetofNode)
            n.args.to_a

          when NodeKind::Alignof
            n = node.as(AlignofNode)
            n.args.to_a

          when NodeKind::InstanceAlignof
            n = node.as(InstanceAlignofNode)
            n.args.to_a

          when NodeKind::Typeof
            n = node.as(TypeofNode)
            n.args.to_a

          when NodeKind::Uninitialized
            n = node.as(UninitializedNode)
            [n.type]

          when NodeKind::Super
            n = node.as(SuperNode)
            n.args.try(&.to_a) || [] of ExprId

          when NodeKind::PreviousDef
            n = node.as(PreviousDefNode)
            n.args.try(&.to_a) || [] of ExprId

          when NodeKind::As
            n = node.as(AsNode)
            [n.expression]

          when NodeKind::AsQuestion
            n = node.as(AsQuestionNode)
            [n.expression]

          when NodeKind::IsA
            n = node.as(IsANode)
            [n.expression]

          when NodeKind::RespondsTo
            n = node.as(RespondsToNode)
            [n.expression, n.method_name]

          when NodeKind::With
            n = node.as(WithNode)
            children = [n.receiver] of ExprId
            n.body.each { |expr| children << expr }
            children

          when NodeKind::Generic
            n = node.as(GenericNode)
            children = [n.base_type] of ExprId
            n.type_args.each { |type_arg| children << type_arg }
            children

          when NodeKind::Path
            n = node.as(PathNode)
            children = [] of ExprId
            if left = n.left
              children << left unless left.invalid?
            end
            children << n.right
            children

          when NodeKind::Out
            # OutNode has only identifier, no child expressions
            [] of ExprId

          when NodeKind::Lib
            n = node.as(LibNode)
            (n.body || [] of ExprId).to_a

          when NodeKind::Fun
            n = node.as(FunNode)
            children = [] of ExprId
            append_parameter_defaults(children, n.params)
            children

          when NodeKind::Alias
            # AliasNode has value as Slice(UInt8), not ExprId
            [] of ExprId

          when NodeKind::AnnotationDef
            [] of ExprId

          when NodeKind::Asm
            n = node.as(AsmNode)
            n.args.to_a

          else
            # Leaf nodes: Number, Identifier, String, Bool, Nil, Symbol, etc.
            [] of ExprId
          end
        end

        private def self.append_parameter_defaults(children : Array(ExprId), params : Array(Parameter)?) : Nil
          return unless params
          params.each do |param|
            if default_value = param.default_value
              children << default_value unless default_value.invalid?
            end
          end
        end

        private def self.append_accessor_defaults(children : Array(ExprId), specs : Array(AccessorSpec)) : Nil
          specs.each do |spec|
            if default_value = spec.default_value
              children << default_value unless default_value.invalid?
            end
          end
        end

        # Iterator version that yields children
        @[NoInline]
        def self.each_child_expr(arena : ArenaLike, expr_id : ExprId, &block : ExprId ->)
          get_child_exprs(arena, expr_id).each do |child|
            yield child
          end
        end
      end
    end
  end
end
