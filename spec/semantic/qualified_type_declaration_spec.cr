require "spec"

require "../../src/compiler/frontend/lexer"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/semantic/context"
require "../../src/compiler/semantic/collectors/symbol_collector"
require "../../src/compiler/semantic/symbol"

module QualifiedTypeDeclarationSpec
  alias Frontend = Adamas::Compiler::Frontend

  def self.collect(source : String) : {Adamas::Compiler::Semantic::Context, Adamas::Compiler::Semantic::SymbolCollector}
    program = Frontend::Parser.new(Frontend::Lexer.new(source)).parse_program
    context = Adamas::Compiler::Semantic::Context.new(Adamas::Compiler::Semantic::SymbolTable.new)
    collector = Adamas::Compiler::Semantic::SymbolCollector.new(program, context)
    collector.collect
    {context, collector}
  end
end

describe Adamas::Compiler::Semantic::SymbolCollector do
  it "places qualified enums and aliases according to rooted, self, parent, and fallback paths" do
    context, collector = QualifiedTypeDeclarationSpec.collect(<<-CR)
      module QualifiedDeclRoot
        module QualifiedDeclNested
          enum QualifiedDeclNested::SelfEnum
            SelfValue
          end

          enum QualifiedDeclRoot::QualifiedDeclNested::FallbackEnum
            FallbackValue
          end

          enum ::QualifiedDeclGlobal::RootEnum
            RootValue
          end

          alias ::QualifiedDeclGlobal::RootAlias = Int32
          enum LocalEnum
            LocalValue
          end
          alias LocalAlias = String
        end
      end

      class QualifiedDeclParent
        module QualifiedDeclTypes
        end
      end

      class QualifiedDeclChild < QualifiedDeclParent
        enum QualifiedDeclTypes::ParentEnum
          ParentValue
        end
        alias QualifiedDeclTypes::ParentAlias = Int32
      end

      module QualifiedDeclIncludedA
        module SharedTypes
        end
      end

      module QualifiedDeclIncludedB
        module SharedTypes
        end
      end

      class QualifiedDeclIncludeUser
        include QualifiedDeclIncludedA
        include QualifiedDeclIncludedB
        enum SharedTypes::IncludedEnum
          IncludedValue
        end
      end

      class QualifiedDeclLocalWins
        include QualifiedDeclIncludedA
        include QualifiedDeclIncludedB
        module SharedTypes
        end
        enum SharedTypes::LocalEnum
          LocalValue
        end
      end

      module QualifiedDeclAliasTarget
        class MutexLike
        end
      end
      alias QualifiedDeclMutex = QualifiedDeclAliasTarget::MutexLike
      alias QualifiedDeclMutex::Protection = Int32
    CR

    collector.diagnostics.should be_empty

    root = context.symbol_table
    outer = root.lookup_local("QualifiedDeclRoot").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    nested = outer.as(Adamas::Compiler::Semantic::ModuleSymbol).scope.lookup_local("QualifiedDeclNested").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    nested_scope = nested.as(Adamas::Compiler::Semantic::ModuleSymbol).scope

    self_enum = nested_scope.lookup_local("SelfEnum").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    self_enum.as(Adamas::Compiler::Semantic::EnumSymbol).name.should eq("SelfEnum")

    fallback_root = nested_scope.lookup_local("QualifiedDeclRoot").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    fallback_nested = fallback_root.as(Adamas::Compiler::Semantic::ModuleSymbol).scope.lookup_local("QualifiedDeclNested").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    fallback_enum = fallback_nested.as(Adamas::Compiler::Semantic::ModuleSymbol).scope.lookup_local("FallbackEnum").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    fallback_enum.as(Adamas::Compiler::Semantic::EnumSymbol).name.should eq("FallbackEnum")

    rooted = root.lookup_local("QualifiedDeclGlobal").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    rooted_scope = rooted.as(Adamas::Compiler::Semantic::ModuleSymbol).scope
    rooted_scope.lookup_local("RootEnum").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    rooted_alias = rooted_scope.lookup_local("RootAlias").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    rooted_alias.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("Int32")

    nested_scope.lookup_local("LocalEnum").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    local_alias = nested_scope.lookup_local("LocalAlias").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    local_alias.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("String")

    parent = root.lookup_local("QualifiedDeclParent").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    parent_types = parent.as(Adamas::Compiler::Semantic::ClassSymbol).scope.lookup_local("QualifiedDeclTypes").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    parent_types_scope = parent_types.as(Adamas::Compiler::Semantic::ModuleSymbol).scope
    parent_types_scope.lookup_local("ParentEnum").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    parent_alias = parent_types_scope.lookup_local("ParentAlias").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    parent_alias.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("Int32")

    child = root.lookup_local("QualifiedDeclChild").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    child.as(Adamas::Compiler::Semantic::ClassSymbol).scope.lookup_local("QualifiedDeclTypes").should be_nil

    included_b = root.lookup_local("QualifiedDeclIncludedB").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    included_types = included_b.as(Adamas::Compiler::Semantic::ModuleSymbol).scope.lookup_local("SharedTypes").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    included_types.as(Adamas::Compiler::Semantic::ModuleSymbol).scope.lookup_local("IncludedEnum").should be_a(Adamas::Compiler::Semantic::EnumSymbol)

    local_wins = root.lookup_local("QualifiedDeclLocalWins").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    local_types = local_wins.as(Adamas::Compiler::Semantic::ClassSymbol).scope.lookup_local("SharedTypes").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    local_types.as(Adamas::Compiler::Semantic::ModuleSymbol).scope.lookup_local("LocalEnum").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    included_a = root.lookup_local("QualifiedDeclIncludedA").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    included_a_types = included_a.as(Adamas::Compiler::Semantic::ModuleSymbol).scope.lookup_local("SharedTypes").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    included_a_types.as(Adamas::Compiler::Semantic::ModuleSymbol).scope.lookup_local("LocalEnum").should be_nil

    alias_target = root.lookup_local("QualifiedDeclAliasTarget").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    mutex_like = alias_target.as(Adamas::Compiler::Semantic::ModuleSymbol).scope.lookup_local("MutexLike").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    protection = mutex_like.as(Adamas::Compiler::Semantic::ClassSymbol).scope.lookup_local("Protection").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    protection.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("Int32")
  end

  it "resolves alias RHS paths through enclosing lexical namespaces" do
    context, collector = QualifiedTypeDeclarationSpec.collect(<<-CR)
      module QualifiedDeclAliasRhsTarget
        class Holder
        end
      end

      class QualifiedDeclAliasRhsScope
        alias Relative = QualifiedDeclAliasRhsTarget::Holder
        alias Rooted = ::QualifiedDeclAliasRhsTarget::Holder
        alias Relative::RelativeValue = Int32
        alias Rooted::RootedValue = String
      end
    CR

    collector.diagnostics.should be_empty

    root = context.symbol_table
    target = root.lookup_local("QualifiedDeclAliasRhsTarget").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    holder = target.as(Adamas::Compiler::Semantic::ModuleSymbol).scope.lookup_local("Holder").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    holder_scope = holder.as(Adamas::Compiler::Semantic::ClassSymbol).scope
    relative_value = holder_scope.lookup_local("RelativeValue").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    relative_value.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("Int32")
    rooted_value = holder_scope.lookup_local("RootedValue").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    rooted_value.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("String")

    alias_scope = root.lookup_local("QualifiedDeclAliasRhsScope").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    rooted = alias_scope.as(Adamas::Compiler::Semantic::ClassSymbol).scope.lookup_local("Rooted").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    rooted.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("::QualifiedDeclAliasRhsTarget::Holder")
  end

  it "preserves existing non-container symbols when a qualified declaration prefix is invalid" do
    context, collector = QualifiedTypeDeclarationSpec.collect(<<-CR)
      enum QualifiedDeclExistingEnumPrefix
        Original
      end
      alias QualifiedDeclExistingEnumPrefix::Nested = Int32

      QualifiedDeclExistingConstantPrefix = 1
      enum QualifiedDeclExistingConstantPrefix::Nested
        NestedValue
      end

      enum QualifiedDeclAliasEnumTarget
        Original
      end
      alias QualifiedDeclExistingEnumAliasPrefix = QualifiedDeclAliasEnumTarget
      alias QualifiedDeclExistingEnumAliasPrefix::Nested = Int32

      alias QualifiedDeclExistingUnionAliasPrefix = Int32 | String
      alias QualifiedDeclExistingUnionAliasPrefix::Nested = Int32
    CR

    collector.diagnostics.count { |diagnostic| diagnostic.code == "E2001" }.should eq(4)

    root = context.symbol_table
    enum_prefix = root.lookup_local("QualifiedDeclExistingEnumPrefix").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    enum_prefix.as(Adamas::Compiler::Semantic::EnumSymbol).members.has_key?("Original").should be_true
    enum_prefix.as(Adamas::Compiler::Semantic::EnumSymbol).scope.lookup_local("Nested").should be_nil

    root.lookup_local("QualifiedDeclExistingConstantPrefix").should be_a(Adamas::Compiler::Semantic::ConstantSymbol)

    enum_alias_prefix = root.lookup_local("QualifiedDeclExistingEnumAliasPrefix").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    enum_alias_prefix.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("QualifiedDeclAliasEnumTarget")

    union_alias_prefix = root.lookup_local("QualifiedDeclExistingUnionAliasPrefix").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    union_alias_prefix.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("Int32|String")
  end

  it "does not replace a namespace implicitly created by a qualified enum declaration" do
    context, collector = QualifiedTypeDeclarationSpec.collect(<<-CR)
      enum QualifiedDeclGuardPrefix::Level
        Active
      end

      enum QualifiedDeclGuardPrefix
        Replacement
      end
      alias QualifiedDeclGuardPrefix = Int32
      class QualifiedDeclGuardPrefix
      end
      struct QualifiedDeclGuardPrefix
      end
    CR

    collector.diagnostics.count { |diagnostic| diagnostic.code == "E2001" }.should eq(4)
    messages = collector.diagnostics.map(&.message)
    messages.should contain("cannot redefine module 'QualifiedDeclGuardPrefix' as enum")
    messages.should contain("cannot redefine module 'QualifiedDeclGuardPrefix' as alias")
    messages.should contain("cannot redefine module 'QualifiedDeclGuardPrefix' as class")
    messages.should contain("cannot redefine module 'QualifiedDeclGuardPrefix' as struct")

    prefix = context.symbol_table.lookup_local("QualifiedDeclGuardPrefix").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    prefix = prefix.as(Adamas::Compiler::Semantic::ModuleSymbol)
    prefix.scope.owner_module.should eq(prefix)
    level = prefix.scope.lookup_local("Level").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    level = level.as(Adamas::Compiler::Semantic::EnumSymbol)
    level.members.has_key?("Active").should be_true
    prefix.scope.lookup_local("Replacement").should be_nil
  end

  it "reopens an implicit namespace and accepts a later qualified alias beside an earlier enum" do
    context, collector = QualifiedTypeDeclarationSpec.collect(<<-CR)
      enum QualifiedDeclGuardReopened::Original
        Active
      end

      alias QualifiedDeclGuardReopened::LaterAlias = String

      module QualifiedDeclGuardReopened
        enum Reopened
          ReopenedValue
        end
      end
    CR

    collector.diagnostics.should be_empty

    reopened = context.symbol_table.lookup_local("QualifiedDeclGuardReopened").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    reopened = reopened.as(Adamas::Compiler::Semantic::ModuleSymbol)
    reopened.scope.owner_module.should eq(reopened)
    reopened.scope.lookup_local("Original").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    reopened.scope.lookup_local("Reopened").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    later_alias = reopened.scope.lookup_local("LaterAlias").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    later_alias = later_alias.as(Adamas::Compiler::Semantic::AliasSymbol)
    later_alias.target.should eq("String")
  end

  it "seeds root predefined source namespaces with their real declaration kinds" do
    context, collector = QualifiedTypeDeclarationSpec.collect(<<-CR)
      enum String::Level
        Active
      end
      class String
      end

      enum Regex::Level
        Active
      end
      class Regex
      end

      enum Exception::Status
        Raised
      end
      class Exception
      end

      enum Array::Entry
        ArrayValue
      end
      class Array(T)
      end

      enum Slice::Entry
        SliceValue
      end
      struct Slice(T)
      end

      enum Int32::Bits
        Bit
      end
      struct Int32
      end

      enum Enumerable::Entry
        EnumerableValue
      end
      module Enumerable(T)
      end

      enum GC::Callbacks
        Callback
      end
      module GC
      end

      module QualifiedDeclNestedBuiltinOwner
      end
      enum QualifiedDeclNestedBuiltinOwner::Regex::Level
        NestedValue
      end

      enum Set::Level
        SetValue
      end
      class Set
      end

      enum Iterator::Level
        IteratorValue
      end
      class Iterator
      end

      enum Void::Level
        VoidValue
      end
      class Void
      end

      enum NoReturn::Level
        NoReturnValue
      end
      class NoReturn
      end
    CR

    collector.diagnostics.count { |diagnostic| diagnostic.code == "E2001" }.should eq(4)
    collector.diagnostics.map(&.message).should contain("cannot redefine module 'Set' as class")
    collector.diagnostics.map(&.message).should contain("cannot redefine module 'Iterator' as class")
    collector.diagnostics.map(&.message).should contain("cannot redefine module 'Void' as class")
    collector.diagnostics.map(&.message).should contain("cannot redefine module 'NoReturn' as class")

    root = context.symbol_table
    string_symbol = root.lookup_local("String").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    string_symbol.as(Adamas::Compiler::Semantic::ClassSymbol).superclass_name.should eq("Reference")

    regex_symbol = root.lookup_local("Regex").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    regex = regex_symbol.as(Adamas::Compiler::Semantic::ClassSymbol)
    regex.superclass_name.should eq("Reference")
    regex.scope.lookup_local("Level").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    regex.scope.lookup_local("Level").as(Adamas::Compiler::Semantic::EnumSymbol).members.has_key?("Active").should be_true

    exception_symbol = root.lookup_local("Exception").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    exception = exception_symbol.as(Adamas::Compiler::Semantic::ClassSymbol)
    exception.superclass_name.should eq("Reference")
    exception.scope.lookup_local("Status").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    exception.scope.lookup_local("Status").as(Adamas::Compiler::Semantic::EnumSymbol).members.has_key?("Raised").should be_true

    array = root.lookup_local("Array").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    array = array.as(Adamas::Compiler::Semantic::ClassSymbol)
    array.superclass_name.should eq("Reference")
    array.type_parameters.should eq(["T"] of String)

    slice = root.lookup_local("Slice").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    slice = slice.as(Adamas::Compiler::Semantic::ClassSymbol)
    slice.is_struct?.should be_true
    slice.superclass_name.should eq("Struct")
    slice.type_parameters.should eq(["T"] of String)

    int32 = root.lookup_local("Int32").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    int32 = int32.as(Adamas::Compiler::Semantic::ClassSymbol)
    int32.is_struct?.should be_true
    int32.superclass_name.should eq("Int")

    enumerable = root.lookup_local("Enumerable").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    enumerable = enumerable.as(Adamas::Compiler::Semantic::ModuleSymbol)
    enumerable.type_parameters.should eq(["T"] of String)
    enumerable.scope.lookup_local("Entry").should be_a(Adamas::Compiler::Semantic::EnumSymbol)

    gc = root.lookup_local("GC").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    gc = gc.as(Adamas::Compiler::Semantic::ModuleSymbol)
    gc.scope.lookup_local("Callbacks").should be_a(Adamas::Compiler::Semantic::EnumSymbol)

    nested_owner = root.lookup_local("QualifiedDeclNestedBuiltinOwner").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    nested_owner = nested_owner.as(Adamas::Compiler::Semantic::ModuleSymbol)
    nested_regex = nested_owner.scope.lookup_local("Regex").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    nested_regex = nested_regex.as(Adamas::Compiler::Semantic::ModuleSymbol)
    nested_regex.scope.lookup_local("Level").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    root.lookup_local("Regex").should be_a(Adamas::Compiler::Semantic::ClassSymbol)

    {"Set", "Iterator", "Void", "NoReturn"}.each do |name|
      prefix_symbol = root.lookup_local(name).should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
      prefix = prefix_symbol.as(Adamas::Compiler::Semantic::ModuleSymbol)
      level_symbol = prefix.scope.lookup_local("Level").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
      level = level_symbol.as(Adamas::Compiler::Semantic::EnumSymbol)
      level.members.empty?.should be_false
    end
  end

  it "keeps the predefined source type catalog limited to nominal source namespaces" do
    {"Object", "String", "Regex", "Exception", "Array", "Slice", "Int32", "Enumerable", "GC"}.each do |name|
      Adamas::Compiler::PredefinedSourceTypes.namespace?(name).should be_true
      Adamas::Compiler::PredefinedSourceTypes.metadata(name).should_not be_nil
    end

    {"Set", "Iterator", "Void", "NoReturn", "AlwaysInline", "ARGC_UNSAFE"}.each do |name|
      Adamas::Compiler::PredefinedSourceTypes.namespace?(name).should be_false
      Adamas::Compiler::PredefinedSourceTypes.metadata(name).should be_nil
    end

    Adamas::Compiler::PredefinedSourceTypes.metadata("Array").not_nil!.type_parameters.should eq(["T"] of String)
    Adamas::Compiler::PredefinedSourceTypes.metadata("Slice").not_nil!.is_struct.should be_true
    Adamas::Compiler::PredefinedSourceTypes.metadata("Int32").not_nil!.superclass_name.should eq("Int")
    Adamas::Compiler::PredefinedSourceTypes.metadata("Enumerable").not_nil!.is_module.should be_true
    Adamas::Compiler::PredefinedSourceTypes.metadata("GC").not_nil!.is_module.should be_true
    Adamas::Compiler::PredefinedSourceTypes.non_generic_class_metadata("Regex").should eq({false, false})
    Adamas::Compiler::PredefinedSourceTypes.non_generic_class_metadata("Value").should eq({true, true})
    Adamas::Compiler::PredefinedSourceTypes.non_generic_class_metadata("Array").should be_nil
  end

  it "rejects module definitions through aliases to non-module types" do
    context, collector = QualifiedTypeDeclarationSpec.collect(<<-CR)
      alias QualifiedDeclAliasUnionModule = Int32 | String
      module QualifiedDeclAliasUnionModule
      end

      class QualifiedDeclAliasClassTarget
      end
      alias QualifiedDeclAliasClassModule = QualifiedDeclAliasClassTarget
      module QualifiedDeclAliasClassModule
      end

      alias QualifiedDeclAliasVoidModule = Void
      module QualifiedDeclAliasVoidModule
      end
    CR

    collector.diagnostics.count { |diagnostic| diagnostic.code == "E2001" }.should eq(3)

    root = context.symbol_table
    union_alias = root.lookup_local("QualifiedDeclAliasUnionModule").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    union_alias.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("Int32|String")
    class_alias = root.lookup_local("QualifiedDeclAliasClassModule").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    class_alias.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("QualifiedDeclAliasClassTarget")
    void_alias = root.lookup_local("QualifiedDeclAliasVoidModule").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    void_alias.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("Void")
  end

  it "reopens a module through an alias without replacing the alias entry" do
    context, collector = QualifiedTypeDeclarationSpec.collect(<<-CR)
      module QualifiedDeclAliasModuleActual
      end
      alias QualifiedDeclAliasModuleOwner = QualifiedDeclAliasModuleActual

      module QualifiedDeclAliasModuleOwner
        enum Level
          Active
        end
      end

      class QualifiedDeclAliasClassOwner
      end
      alias QualifiedDeclAliasClassWrapper = QualifiedDeclAliasClassOwner
      module QualifiedDeclAliasClassWrapper::Nested
        enum Level
          NestedActive
        end
      end
    CR

    collector.diagnostics.should be_empty

    root = context.symbol_table
    alias_symbol = root.lookup_local("QualifiedDeclAliasModuleOwner").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    alias_symbol.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("QualifiedDeclAliasModuleActual")

    actual_module = root.lookup_local("QualifiedDeclAliasModuleActual").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    actual = actual_module.as(Adamas::Compiler::Semantic::ModuleSymbol)
    actual.scope.owner_module.should eq(actual)
    level = actual.scope.lookup_local("Level").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
    level.as(Adamas::Compiler::Semantic::EnumSymbol).members.has_key?("Active").should be_true

    class_alias = root.lookup_local("QualifiedDeclAliasClassWrapper").should be_a(Adamas::Compiler::Semantic::AliasSymbol)
    class_alias.as(Adamas::Compiler::Semantic::AliasSymbol).target.should eq("QualifiedDeclAliasClassOwner")
    actual_class = root.lookup_local("QualifiedDeclAliasClassOwner").should be_a(Adamas::Compiler::Semantic::ClassSymbol)
    nested = actual_class.as(Adamas::Compiler::Semantic::ClassSymbol).scope.lookup_local("Nested").should be_a(Adamas::Compiler::Semantic::ModuleSymbol)
    nested.as(Adamas::Compiler::Semantic::ModuleSymbol).scope.lookup_local("Level").should be_a(Adamas::Compiler::Semantic::EnumSymbol)
  end
end
