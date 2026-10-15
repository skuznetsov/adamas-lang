require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

private def lower_abstract_numeric_return(source : String) : Adamas::HIR::AstToHir
  parser = Adamas::Compiler::Frontend::Parser.new(
    Adamas::Compiler::Frontend::Lexer.new(source),
  )
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena
  converter = Adamas::HIR::AstToHir.new(
    arena,
    sources_by_arena: {arena.object_id.to_u64 => source},
  )
  converter.arena = arena
  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  classes = [] of Adamas::Compiler::Frontend::ClassNode
  defs = [] of Adamas::Compiler::Frontend::DefNode
  main = [] of UInt64
  program.roots.each do |id|
    case node = arena[id]
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
      classes << node
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
      defs << node
    else
      main << id.index.to_u64
    end
  end
  defs.each { |node| converter.lower_def(node) }
  modules.each { |node| converter.lower_module(node) }
  classes.each { |node| converter.lower_class(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  converter
end

private def abstract_numeric_return_type(converter, name)
  function = converter.module.function_by_name(name)
  function.should_not be_nil
  function.not_nil!.return_type
end

describe "Abstract numeric return constraints" do
  it "keeps a concrete wide module result under Int" do
    converter = lower_abstract_numeric_return(<<-CRYSTAL)
      module NumericModuleResult
        extend self
        def value : Int
          0x1_0000_002a_u64
        end
      end
      NumericModuleResult.value
    CRYSTAL
    abstract_numeric_return_type(converter, "NumericModuleResult.value").should eq(Adamas::HIR::TypeRef::UINT64)
  end

  it "infers an explicit return without including its dead nil tail" do
    converter = lower_abstract_numeric_return(<<-CRYSTAL)
      module NumericExplicitResult
        extend self
        def value : Int
          return 0x1_0000_002a_u64
        end
      end
      NumericExplicitResult.value
    CRYSTAL
    abstract_numeric_return_type(converter, "NumericExplicitResult.value").should eq(Adamas::HIR::TypeRef::UINT64)
  end

  it "keeps a concrete class method result under Int" do
    converter = lower_abstract_numeric_return(<<-CRYSTAL)
      class NumericClassResult
        def self.value : Int
          0x1_0000_002a_u64
        end
      end
      NumericClassResult.value
    CRYSTAL
    abstract_numeric_return_type(converter, "NumericClassResult.value").should eq(Adamas::HIR::TypeRef::UINT64)
  end

  it "keeps a concrete free function result under Int" do
    converter = lower_abstract_numeric_return(<<-CRYSTAL)
      def numeric_free_result : Int
        0x1_0000_002a_u64
      end
      numeric_free_result()
    CRYSTAL
    abstract_numeric_return_type(converter, "numeric_free_result").should eq(Adamas::HIR::TypeRef::UINT64)
  end

  it "rejects abstract numeric unions like the original Crystal compiler" do
    expect_raises(Adamas::HIR::LoweringError, /abstract numeric.*union/) do
      lower_abstract_numeric_return(<<-CRYSTAL)
        module NumericNullableResult
          extend self
          def value(flag : Bool) : Int | Nil
            if flag
              0x1_0000_002a_u64
            else
              nil
            end
          end
        end
        NumericNullableResult.value(true)
      CRYSTAL
    end
  end

  it "keeps a wide free-function argument and its inferred result" do
    converter = lower_abstract_numeric_return(<<-CRYSTAL)
      def numeric_free_identity(value : Int) : Int
        value
      end
      numeric_free_identity(0x1_0000_002a_u64)
    CRYSTAL
    function = converter.module.function_by_name("numeric_free_identity$UInt64")
    function.should_not be_nil
    function.not_nil!.params.first.type.should eq(Adamas::HIR::TypeRef::UINT64)
    function.not_nil!.return_type.should eq(Adamas::HIR::TypeRef::UINT64)
  end

  it "publishes a concrete Number result before a zero-argument call is emitted" do
    converter = lower_abstract_numeric_return(<<-CRYSTAL)
      module NumericCallResult
        extend self
        def value : Number
          0x1_0000_002a_u64
        end
      end
      NumericCallResult.value
    CRYSTAL
    main = converter.module.function_by_name("__adamas_main")
    main.should_not be_nil
    call = main.not_nil!.blocks.flat_map(&.instructions).find do |instruction|
      instruction.as?(Adamas::HIR::Call).try(&.method_name) == "NumericCallResult.value"
    end
    call.should_not be_nil
    call.not_nil!.type.should eq(Adamas::HIR::TypeRef::UINT64)
  end

  it "rejects a nonnumeric body instead of treating Int as an inference hint" do
    expect_raises(Adamas::HIR::LoweringError, /return.*Int/) do
      lower_abstract_numeric_return(<<-CRYSTAL)
        module NumericInvalidResult
          extend self
          def value : Int
            "invalid"
          end
        end
        NumericInvalidResult.value
      CRYSTAL
    end
  end

  it "keeps a concrete Float result under Float" do
    converter = lower_abstract_numeric_return(<<-CRYSTAL)
      module NumericFloatResult
        extend self
        def value : Float
          42.5_f64
        end
      end
      NumericFloatResult.value
    CRYSTAL
    abstract_numeric_return_type(converter, "NumericFloatResult.value").should eq(Adamas::HIR::TypeRef::FLOAT64)
  end

  it "keeps a concrete integer result under Number" do
    converter = lower_abstract_numeric_return(<<-CRYSTAL)
      module NumericNumberResult
        extend self
        def value : Number
          0x1_0000_002a_u64
        end
      end
      NumericNumberResult.value
    CRYSTAL
    abstract_numeric_return_type(converter, "NumericNumberResult.value").should eq(Adamas::HIR::TypeRef::UINT64)
  end

  it "retains a concrete return annotation" do
    converter = lower_abstract_numeric_return(<<-CRYSTAL)
      module NumericConcreteResult
        extend self
        def value : UInt64
          0x1_0000_002a_u64
        end
      end
      NumericConcreteResult.value
    CRYSTAL
    abstract_numeric_return_type(converter, "NumericConcreteResult.value").should eq(Adamas::HIR::TypeRef::UINT64)
  end
end
