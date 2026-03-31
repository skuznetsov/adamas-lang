require "set"
require "./symbol"

module CrystalV2
  module Compiler
    module Semantic
      record IncludedModuleRef, symbol : ModuleSymbol, type_arg_names : Array(String)? = nil do
        delegate name, to: symbol
        delegate scope, to: symbol
      end

      class SymbolTable
        getter parent : SymbolTable?
        getter included_modules : Array(IncludedModuleRef)
        property owner_module : ModuleSymbol?

        def initialize(@parent : SymbolTable? = nil)
          @symbols = {} of String => Symbol
          @macro_symbols = {} of String => MacroSymbol
          @included_modules = [] of IncludedModuleRef
          @owner_module = nil
        end

        def define(name : String, symbol : Symbol)
          if existing = @symbols[name]?
            raise SymbolRedefinitionError.new(name, existing, symbol)
          end
          @symbols[name] = symbol
        end

        def redefine(name : String, symbol : Symbol)
          @symbols[name] = symbol
        end

        def define_macro(name : String, symbol : MacroSymbol)
          if existing = @macro_symbols[name]?
            raise SymbolRedefinitionError.new(name, existing, symbol)
          end
          @macro_symbols[name] = symbol
        end

        def redefine_macro(name : String, symbol : MacroSymbol)
          @macro_symbols[name] = symbol
        end

        def lookup(name : String) : Symbol?
          @symbols[name]? || lookup_included(name, Set(SymbolTable).new) || @parent.try(&.lookup(name))
        end

        def lookup_macro(name : String) : MacroSymbol?
          @macro_symbols[name]? || lookup_macro_included(name, Set(SymbolTable).new) || @parent.try(&.lookup_macro(name))
        end

        def local?(name : String) : Bool
          @symbols.has_key?(name) || @macro_symbols.has_key?(name)
        end

        def lookup_local(name : String) : Symbol?
          @symbols[name]?
        end

        def lookup_local_macro(name : String) : MacroSymbol?
          @macro_symbols[name]?
        end

        def each_local_symbol(&block : String, Symbol ->)
          @symbols.each do |key, value|
            yield key, value
          end
          @macro_symbols.each do |key, value|
            yield key, value
          end
        end

        def include_module(symbol : ModuleSymbol, type_arg_names : Array(String)? = nil)
          ref = IncludedModuleRef.new(symbol, type_arg_names)
          unless @included_modules.includes?(ref)
            @included_modules << ref
          end
        end

        private getter symbols : Hash(String, Symbol)
        private getter macro_symbols : Hash(String, MacroSymbol)

        private def lookup_included(name : String, visited : Set(SymbolTable)) : Symbol?
          @included_modules.each do |mod_ref|
            if result = lookup_in_scope(mod_ref.scope, name, visited)
              return result
            end
          end
          nil
        end

        private def lookup_macro_included(name : String, visited : Set(SymbolTable)) : MacroSymbol?
          @included_modules.each do |mod_ref|
            if result = lookup_macro_in_scope(mod_ref.scope, name, visited)
              return result
            end
          end
          nil
        end

        private def lookup_in_scope(table : SymbolTable, name : String, visited : Set(SymbolTable)) : Symbol?
          return nil unless visited.add?(table)

          if symbol = table.lookup_local(name)
            return symbol
          end

          table.included_modules.each do |mod_ref|
            if result = lookup_in_scope(mod_ref.scope, name, visited)
              return result
            end
          end

          if parent = table.parent
            return lookup_in_scope(parent, name, visited)
          end

          nil
        end

        private def lookup_macro_in_scope(table : SymbolTable, name : String, visited : Set(SymbolTable)) : MacroSymbol?
          return nil unless visited.add?(table)

          if symbol = table.lookup_local_macro(name)
            return symbol
          end

          table.included_modules.each do |mod_ref|
            if result = lookup_macro_in_scope(mod_ref.scope, name, visited)
              return result
            end
          end

          if parent = table.parent
            return lookup_macro_in_scope(parent, name, visited)
          end

          nil
        end
      end

      class SymbolRedefinitionError < Exception
        getter name : String
        getter existing : Symbol
        getter new_symbol : Symbol

        def initialize(@name : String, @existing : Symbol, @new_symbol : Symbol)
          super("symbol '#{name}' already defined")
        end
      end
    end
  end
end
