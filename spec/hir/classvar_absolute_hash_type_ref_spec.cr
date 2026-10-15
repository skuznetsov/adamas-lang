require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"

class Adamas::HIR::AstToHir
  def __test_classvar_hash_type(value : Adamas::Compiler::Frontend::HashLiteralNode, owner : String) : Adamas::HIR::TypeRef
    previous_class = @current_class
    @current_class = owner
    infer_type_from_class_ivar_assign(value)
  ensure
    @current_class = previous_class
  end

  def __test_annotation_type_ref(name : String, owner : String) : Adamas::HIR::TypeRef
    annotation_type_ref(name, owner)
  end

  def __test_type_name(type : Adamas::HIR::TypeRef) : String
    get_type_name_from_ref(type)
  end

  def __test_type_arguments(type : Adamas::HIR::TypeRef) : Array(Adamas::HIR::TypeRef)
    @module.get_type_descriptor(type).not_nil!.type_params
  end

  def __test_normalized_type_name(name : String, owner : String) : String
    normalize_declared_type_name(name, owner)
  end

  def __test_resolved_alias_target(name : String, owner : String) : String
    resolve_alias_target(name, owner)
  end

  def __test_registered_alias_target(name : String) : String?
    @type_aliases[name]?
  end

  def __test_direct_type_name(name : String) : Adamas::HIR::TypeRef
    type_ref_for_name(name)
  end
end

private def classvar_hash_fixture(source : String) : Tuple(Adamas::HIR::AstToHir, Adamas::Compiler::Frontend::AstArena, Adamas::Compiler::Frontend::Program)
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(source))
  program = parser.parse_program
  parser.diagnostics.should be_empty
  arena = program.arena.as(Adamas::Compiler::Frontend::AstArena)
  converter = Adamas::HIR::AstToHir.new(arena)
  converter.arena = arena
  program.roots.each do |root_id|
    case node = arena[root_id]
    when Adamas::Compiler::Frontend::EnumNode
      converter.register_enum(node)
    when Adamas::Compiler::Frontend::ModuleNode
      converter.register_module(node)
    end
  end
  {converter, arena, program}
end

private def classvar_hash_initializer(arena : Adamas::Compiler::Frontend::AstArena, program : Adamas::Compiler::Frontend::Program, name : String) : Adamas::Compiler::Frontend::HashLiteralNode
  seen = [] of String
  kinds = [] of String
  target_id : Adamas::Compiler::Frontend::ExprId? = nil
  index = 0
  while index < arena.size
    node_id = Adamas::Compiler::Frontend::ExprId.new(index)
    node = arena[node_id]
    kinds << Adamas::Compiler::Frontend.node_kind(node).to_s
    classvar = node.as?(Adamas::Compiler::Frontend::ClassVarNode)
    if classvar
      classvar_name = String.new(classvar.name).lstrip('@')
      seen << classvar_name
      if classvar_name == name
        target_id = node_id
        break
      end
    end
    index += 1
  end
  if classvar_id = target_id
    index = 0
    while index < arena.size
      node = arena[Adamas::Compiler::Frontend::ExprId.new(index)]
      if assignment = node.as?(Adamas::Compiler::Frontend::AssignNode)
        if assignment.target == classvar_id
          return arena[assignment.value].as(Adamas::Compiler::Frontend::HashLiteralNode)
        end
      end
      index += 1
    end
  end
  raise "classvar initializer #{name} not found: #{seen.join(",")}; arena=#{arena.size} roots=#{program.roots.size} kinds=#{kinds.join(",")}"
end

describe "classvar Hash type references" do
  it "keeps an absolute enum key rooted despite a colliding owner-relative module" do
    converter, arena, program = classvar_hash_fixture(<<-CRYSTAL)
      enum SignalHashOwnerProbe
        Ready
      end

      module HashOwnerCollision
        module SignalHashOwnerProbe
        end
        alias Handler = ::SignalHashOwnerProbe ->
        @@handlers = {} of ::SignalHashOwnerProbe => Int32
      end
    CRYSTAL

    hash = classvar_hash_initializer(arena, program, "handlers")
    converter.__test_resolved_alias_target("::SignalHashOwnerProbe ->", "HashOwnerCollision").lstrip.starts_with?("::SignalHashOwnerProbe").should be_true
    alias_target = converter.__test_registered_alias_target("HashOwnerCollision::Handler").not_nil!
    alias_target.lstrip.starts_with?("::SignalHashOwnerProbe").should be_true
    handler_ref = converter.__test_annotation_type_ref("Handler", "HashOwnerCollision")
    converter.__test_type_name(handler_ref).should eq("Proc")
    handler_args = converter.__test_type_arguments(handler_ref)
    handler_args.size.should eq(2)
    converter.__test_type_name(handler_args[0]).should eq("SignalHashOwnerProbe")
    handler_args[0].should eq(converter.__test_annotation_type_ref("::SignalHashOwnerProbe", "HashOwnerCollision"))
    converter.__test_type_name(handler_args[1]).should eq("Nil")
    inferred = converter.__test_classvar_hash_type(hash, "HashOwnerCollision")
    key = converter.__test_annotation_type_ref("::SignalHashOwnerProbe", "HashOwnerCollision")
    key.should_not eq(Adamas::HIR::TypeRef::VOID)
    key_name = converter.__test_type_name(key)
    key_name.should eq("SignalHashOwnerProbe")

    inferred_name = converter.__test_type_name(inferred)
    inferred_name.should eq("Hash(SignalHashOwnerProbe, Int32)")
    params = converter.__test_type_arguments(inferred)
    params.size.should eq(2)
    params[0].should eq(key)
    params[1].should eq(converter.__test_direct_type_name("Int32"))
  end

  it "keeps a relative type spelling owner-relative as the opposite control" do
    converter, arena, program = classvar_hash_fixture(<<-CRYSTAL)
      enum SignalHashOwnerProbe
        Ready
      end

      module HashOwnerCollision
        module SignalHashOwnerProbe
        end
        alias Handler = SignalHashOwnerProbe ->
        @@handlers = {} of SignalHashOwnerProbe => Handler
      end
    CRYSTAL

    hash = classvar_hash_initializer(arena, program, "handlers")
    inferred = converter.__test_classvar_hash_type(hash, "HashOwnerCollision")
    params = converter.__test_type_arguments(inferred)
    key_name = converter.__test_type_name(params[0])
    key_name.should eq("HashOwnerCollision::SignalHashOwnerProbe")
  end

  it "keeps a root-qualified enum absolute under a deeply nested signal owner" do
    converter, arena, program = classvar_hash_fixture(<<-CRYSTAL)
      enum Signal
        Ready
      end

      module Crystal::System::Signal
        alias Handler = ::Signal ->
        alias ExplicitHandler = ::Signal -> Nil
        @@handlers = {} of ::Signal => Handler
        @@direct_proc = {} of ::Signal => Proc(::Signal, Nil)
        @@explicit_handlers = {} of ::Signal => ExplicitHandler
      end
    CRYSTAL

    hash = classvar_hash_initializer(arena, program, "handlers")
    root_enum = converter.__test_annotation_type_ref("::Signal", "Crystal::System::Signal")
    root_enum.should_not eq(Adamas::HIR::TypeRef::VOID)
    converter.__test_type_name(root_enum).should eq("Signal")

    inferred = converter.__test_classvar_hash_type(hash, "Crystal::System::Signal")
    params = converter.__test_type_arguments(inferred)
    params.size.should eq(2)
    params[0].should eq(root_enum)
    handler = converter.__test_annotation_type_ref("Handler", "Crystal::System::Signal")
    params[1].should eq(handler)
    handler_args = converter.__test_type_arguments(handler)
    handler_args.size.should eq(2)
    handler_args[0].should eq(root_enum)
    handler_args[1].should eq(converter.__test_direct_type_name("Nil"))

    direct_proc = converter.__test_annotation_type_ref("Proc(::Signal, Nil)", "Crystal::System::Signal")
    direct_hash = classvar_hash_initializer(arena, program, "direct_proc")
    direct_inferred = converter.__test_classvar_hash_type(direct_hash, "Crystal::System::Signal")
    direct_params = converter.__test_type_arguments(direct_inferred)
    direct_params.size.should eq(2)
    direct_params[0].should eq(root_enum)
    direct_params[1].should eq(direct_proc)

    explicit_handler = converter.__test_annotation_type_ref("ExplicitHandler", "Crystal::System::Signal")
    explicit_hash = classvar_hash_initializer(arena, program, "explicit_handlers")
    explicit_inferred = converter.__test_classvar_hash_type(explicit_hash, "Crystal::System::Signal")
    explicit_params = converter.__test_type_arguments(explicit_inferred)
    explicit_params.size.should eq(2)
    explicit_params[0].should eq(root_enum)
    explicit_params[1].should eq(explicit_handler)
    explicit_args = converter.__test_type_arguments(explicit_handler)
    explicit_args[0].should eq(root_enum)
    explicit_args[1].should eq(converter.__test_direct_type_name("Nil"))
  end

end
