require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class ModuleRequiredArgumentReplayProbe < Adamas::HIR::AstToHir
  def requires_exact_binding_for?(
    node : Adamas::Compiler::Frontend::DefNode,
    types : Array(Adamas::HIR::TypeRef),
    has_named_args : Bool = false,
  ) : Bool
    module_method_lacks_callsite_types?(node, types, nil, has_named_args, nil)
  end

  def rejects_missing_bound_required_slot?(
    node : Adamas::Compiler::Frontend::DefNode,
    positional_guess : Array(Adamas::HIR::TypeRef),
    supplied_types : Array(Adamas::HIR::TypeRef),
  ) : Bool
    supplied = [] of SourceCallArgument?
    supplied_types.each do |type|
      supplied << SourceCallArgument.new(type, false)
    end
    binding = SourceCallBinding.new("ModuleRequiredArgumentReplayProbe.target", node, @arena, supplied)
    module_method_lacks_callsite_types?(node, positional_guess, nil, false, binding, @arena)
  end
end

private def lower_module_required_argument_replay(source : String) : Adamas::HIR::AstToHir
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
  converter.no_prelude = true

  modules = [] of Adamas::Compiler::Frontend::ModuleNode
  main = [] of UInt64
  program.roots.each do |root|
    case node = arena[root]
    when Adamas::Compiler::Frontend::LibNode
      converter.register_lib(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
      modules << node
    when Adamas::Compiler::Frontend::ClassNode
      converter.register_class(node)
    when Adamas::Compiler::Frontend::DefNode
      converter.register_function(node)
    else
      main << root.index.to_u64
    end
  end

  modules.each { |node| converter.lower_module(node) }
  converter.lower_main(main)
  converter.flush_pending_functions
  converter.refresh_void_type_params
  converter.flush_deferred_allocators
  converter
end

describe "module required argument specialization replay" do
  it "preserves the required argument slot when a later defaulted call is replayed" do
    converter = lower_module_required_argument_replay(<<-CRYSTAL)
      module ModuleArgumentReplay
        extend self

        def forward(path, mode = 0, follow = true)
          {path, mode, follow}
        end

        def relay_int_bool(path, relay_mode = 0)
          ModuleArgumentReplay.forward(path, 7, false)
        end

        def relay_bool_int(path, relay_mode = 0)
          ModuleArgumentReplay.forward(path, false, 7)
        end
      end

      ModuleArgumentReplay.relay_int_bool("valid")
      ModuleArgumentReplay.relay_bool_int("valid")
    CRYSTAL

    converter.module.has_function_with_body?("ModuleArgumentReplay.forward$Int32_Bool").should be_false
    converter.module.has_function_with_body?("ModuleArgumentReplay.forward$Bool_Int32").should be_false
    converter.module.has_function_with_body?("ModuleArgumentReplay.forward$arity3").should be_false
    converter.module.has_function_with_body?("ModuleArgumentReplay.relay_int_bool$arity2").should be_false
    converter.module.has_function_with_body?("ModuleArgumentReplay.relay_bool_int$arity2").should be_false

    int_bool = converter.module.function_by_name("ModuleArgumentReplay.forward$String_Int32_Bool")
    int_bool.should_not be_nil
    int_bool.not_nil!.params.map(&.type).should eq([
      Adamas::HIR::TypeRef::STRING,
      Adamas::HIR::TypeRef::INT32,
      Adamas::HIR::TypeRef::BOOL,
    ])

    bool_int = converter.module.function_by_name("ModuleArgumentReplay.forward$String_Bool_Int32")
    bool_int.should_not be_nil
    bool_int.not_nil!.params.map(&.type).should eq([
      Adamas::HIR::TypeRef::STRING,
      Adamas::HIR::TypeRef::BOOL,
      Adamas::HIR::TypeRef::INT32,
    ])
  end

  it "waits for untyped required slots beside typed defaults or required formals" do
    converter = lower_module_required_argument_replay(<<-CRYSTAL)
      module ModuleMixedArgumentReplay
        extend self

        def typed_default(path, mode : Int32 = 0, follow = true)
          {path, mode, follow}
        end

        def typed_required(path, mode : Int32, follow = true)
          {path, mode, follow}
        end

        def relay_default(path, relay_mode = 0)
          ModuleMixedArgumentReplay.typed_default(path, 7, false)
        end

        def relay_required(path, relay_mode = 0)
          ModuleMixedArgumentReplay.typed_required(path, 7, false)
        end
      end

      ModuleMixedArgumentReplay.relay_default("default")
      ModuleMixedArgumentReplay.relay_required("required", 7)
    CRYSTAL

    bogus = [
      "ModuleMixedArgumentReplay.typed_default$arity3",
      "ModuleMixedArgumentReplay.typed_default$Int32_Bool",
      "ModuleMixedArgumentReplay.typed_required$arity3",
      "ModuleMixedArgumentReplay.typed_required$Int32_Bool",
    ].select { |name| converter.module.has_function_with_body?(name) }
    bogus.should be_empty
    converter.module.function_by_name("ModuleMixedArgumentReplay.typed_default$String_Int32_Bool").should_not be_nil
    converter.module.function_by_name("ModuleMixedArgumentReplay.typed_required$String_Int32_Bool").should_not be_nil
  end

  it "keeps named, splat, block, default-only, and present defaulted calls" do
    converter = lower_module_required_argument_replay(<<-CRYSTAL)
      module ModuleArgumentCallShapes
        extend self

        def defaulted(path = "default")
          path
        end

        def named(path, mode = 0, follow = true)
          {path, mode, follow}
        end

        def keyword_only(*, path, mode = 0, follow = true)
          {path, mode, follow}
        end

        def positional_and_named_default(path, *, follow_symlinks = true)
          {path, follow_symlinks}
        end

        def splatted(*values)
          values
        end

        def with_splat(path, *values)
          {path, values}
        end

        def with_block(path, mode = 0, &block)
          yield path, mode
        end
      end

      ModuleArgumentCallShapes.defaulted
      ModuleArgumentCallShapes.defaulted("present")
      ModuleArgumentCallShapes.named(follow: false, path: "named")
      ModuleArgumentCallShapes.keyword_only(path: "keyword", follow: false)
      ModuleArgumentCallShapes.positional_and_named_default("path", follow_symlinks: false)
      ModuleArgumentCallShapes.splatted("splat", 7, false)
      ModuleArgumentCallShapes.with_splat("path", *{"splat", 7, false})
      ModuleArgumentCallShapes.with_block("block") { |path, mode| {path, mode} }
    CRYSTAL

    converter.module.has_function_with_body?("ModuleArgumentCallShapes.defaulted$arity1").should be_true
    converter.module.has_function_with_body?("ModuleArgumentCallShapes.defaulted$String").should be_true
    converter.module.has_function_with_body?("ModuleArgumentCallShapes.named$String_Int32_Bool").should be_true
    keyword_only_names = converter.module.functions.select do |function|
      function.name.starts_with?("ModuleArgumentCallShapes.keyword_only$")
    end.map(&.name)
    keyword_only_names.should eq(["ModuleArgumentCallShapes.keyword_only$String_Int32_Bool"])
    converter.module.function_by_name(
      "ModuleArgumentCallShapes.positional_and_named_default$String_Bool",
    ).should_not be_nil
    splatted = converter.module.functions.find do |function|
      function.name.starts_with?("ModuleArgumentCallShapes.splatted$")
    end
    splatted.should_not be_nil
    splatted_function = splatted.not_nil!
    splatted_function.name.should eq("ModuleArgumentCallShapes.splatted$splat$arity1")
    with_splat = converter.module.functions.find do |function|
      function.name.starts_with?("ModuleArgumentCallShapes.with_splat$")
    end
    with_splat.should_not be_nil
    with_splat.not_nil!.name.should eq(
      "ModuleArgumentCallShapes.with_splat$String_Tuple(String, Int32, Bool)",
    )
    converter.module.function_by_name("__adamas_main").should_not be_nil
  end

  it "defers an unbound named-only required slot even with a positional type vector" do
    source = <<-CRYSTAL
      module ModuleNamedOnlyReplay
        def named_only(*, path)
          path
        end
      end
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source),
    )
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    module_node = program.roots.compact_map do |root|
      arena[root].as?(Adamas::Compiler::Frontend::ModuleNode)
    end.first.not_nil!
    def_node = module_node.body.not_nil!.compact_map do |member|
      arena[member].as?(Adamas::Compiler::Frontend::DefNode)
    end.first.not_nil!

    converter = ModuleRequiredArgumentReplayProbe.new(
      arena,
      sources_by_arena: {arena.object_id.to_u64 => source},
    )
    converter.arena = arena
    converter.no_prelude = true
    # This deliberately bypasses the parser's named-argument validation: it
    # models replay with a positional vector but no exact SourceCallBinding.
    converter.requires_exact_binding_for?(def_node, [Adamas::HIR::TypeRef::STRING]).should be_true
    # A replayed "named" flag without the formal-slot binding cannot
    # establish which actual supplied the keyword-only required slot.
    converter.requires_exact_binding_for?(def_node, [Adamas::HIR::TypeRef::STRING], true).should be_true
  end

  it "does not replace a missing required source slot with a positional guess" do
    source = <<-CRYSTAL
      module ModuleMissingBoundSlot
        def target(path, mode : Int32 = 0)
          path
        end
      end
    CRYSTAL
    parser = Adamas::Compiler::Frontend::Parser.new(
      Adamas::Compiler::Frontend::Lexer.new(source),
    )
    program = parser.parse_program
    parser.diagnostics.should be_empty
    arena = program.arena
    module_node = program.roots.compact_map do |root|
      arena[root].as?(Adamas::Compiler::Frontend::ModuleNode)
    end.first.not_nil!
    def_node = module_node.body.not_nil!.compact_map do |member|
      arena[member].as?(Adamas::Compiler::Frontend::DefNode)
    end.first.not_nil!

    converter = ModuleRequiredArgumentReplayProbe.new(
      arena,
      sources_by_arena: {arena.object_id.to_u64 => source},
    )
    converter.arena = arena
    converter.no_prelude = true
    converter.rejects_missing_bound_required_slot?(
      def_node,
      [Adamas::HIR::TypeRef::STRING, Adamas::HIR::TypeRef::BOOL],
      [Adamas::HIR::TypeRef::VOID, Adamas::HIR::TypeRef::INT32],
    ).should be_true
  end

  it "still rejects an invalid required argument at the C boundary" do
    source = <<-CRYSTAL
      lib ModuleArgumentReplayC
        fun accepts(path : UInt8*, mode : Int32, follow : Bool) : Int32
      end

      module ModuleArgumentReplayInvalid
        extend self

        def checked(path, mode = 0, follow = true)
          ModuleArgumentReplayC.accepts(path, mode, follow)
        end
      end

      ModuleArgumentReplayInvalid.checked(123, 7, false)
    CRYSTAL

    error = expect_raises(Adamas::HIR::LoweringError) do
      lower_module_required_argument_replay(source)
    end
    error.message.not_nil!.should contain("argument #1 of 'ModuleArgumentReplayC.accepts' must be Pointer(UInt8), not Int32")
  end

  it "accepts a valid String path with the same C signature" do
    converter = lower_module_required_argument_replay(<<-CRYSTAL)
      lib ModuleArgumentReplayValidC
        fun accepts(path : UInt8*, mode : Int32, follow : Bool) : Int32
      end

      module ModuleArgumentReplayValid
        extend self

        def checked(path, mode = 0, follow = true)
          ModuleArgumentReplayValidC.accepts(path, mode, follow)
        end
      end

      ModuleArgumentReplayValid.checked("valid", 7, false)
    CRYSTAL

    converter.module.has_function_with_body?("ModuleArgumentReplayValid.checked$String_Int32_Bool").should be_true
  end
end
