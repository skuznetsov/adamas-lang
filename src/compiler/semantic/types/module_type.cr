require "./type"
require "../symbol"

module Adamas
  module Compiler
    module Semantic
      # Represents a module constant (namespace)
      class ModuleType < Type
        getter symbol : ModuleSymbol
        getter type_args : Array(Type)?

        def initialize(@symbol : ModuleSymbol, @type_args : Array(Type)? = nil)
        end

        def to_s(io : IO)
          io << @symbol.name
          if args = @type_args
            io << "("
            args.join(io, ", ") { |arg, io| arg.to_s(io) }
            io << ")"
          end
        end

        def ==(other : Type) : Bool
          return false unless other.is_a?(ModuleType)
          return false unless other.symbol == @symbol

          my_args = @type_args
          other_args = other.type_args

          return my_args.nil? && other_args.nil? if my_args.nil? || other_args.nil?

          return false unless my_args.size == other_args.size
          my_args.zip(other_args).all? { |a, b| a == b }
        end

        def hash : UInt64
          @symbol.object_id.hash
        end
      end
    end
  end
end
