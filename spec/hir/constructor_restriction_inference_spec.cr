require "../spec_helper"
require "../../src/compiler/hir/ast_to_hir"
require "../../src/compiler/frontend/parser"
require "../../src/compiler/frontend/lexer"

class Adamas::HIR::AstToHir
  def __test_infer_constructor_expression(expr_id : ExprId, locals : Hash(String, String))
    old_names = @current_typeof_local_names
    old_locals = @current_typeof_locals
    old_version = @infer_type_cache_version
    @current_typeof_local_names = locals
    @current_typeof_locals = locals.transform_values { |name| type_ref_for_name(name) }
    @infer_type_cache_version += 1
    begin
      if inferred = infer_type_from_expr(expr_id, nil)
        get_type_name_from_ref(inferred)
      end
    ensure
      @current_typeof_local_names = old_names
      @current_typeof_locals = old_locals
      @infer_type_cache_version = old_version
    end
  end

  def __test_infer_restricted_constructor(owner : String,
                                        call : Adamas::Compiler::Frontend::CallNode,
                                        locals : Hash(String, String),
                                        caller_type : String? = nil)
    function = @module.create_function("constructor_restriction_probe", TypeRef::NIL)
    ctx = LoweringContext.new(function, @module, @arena)
    locals.each do |name, type_name|
      type = type_ref_for_name(type_name)
      value = function.add_param(name, type)
      ctx.register_local(name, value.id)
      ctx.register_type(value.id, type)
    end
    old_map = @type_param_map.dup
    @type_param_map["T"] = caller_type if caller_type
    begin
      if @generic_templates[owner].type_params.size > 1
        infer_generic_type_args_multi(owner, call.args, ctx, call.named_args)
      elsif inferred = infer_generic_type_arg(owner, call.args, nil, ctx, call.named_args)
        [inferred]
      end
    ensure
      @type_param_map = old_map
    end
  end
end

private def infer_restricted_constructor(initializer : String, call_source : String,
                                         locals : Hash(String, String),
                                         formals : String = "T", caller_type : String? = nil, expression : Bool = false)
  declaration = <<-CRYSTAL
    class RestrictionCarrier(T)
    end
    class RestrictedConstructor(#{formals})
      #{initializer}
    end
  CRYSTAL
  parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(declaration))
  parsed = parser.parse_program
  parser.diagnostics.should be_empty
  converter = Adamas::HIR::AstToHir.new(parsed.arena)
  parsed.roots.each { |root| converter.register_class(parsed.arena[root].as(Adamas::Compiler::Frontend::ClassNode)) }

  # The callsite has a distinct arena: initializer slices must remain owned by
  # the retained declaration arena, even when ExprId indexes overlap.
  call_parser = Adamas::Compiler::Frontend::Parser.new(Adamas::Compiler::Frontend::Lexer.new(call_source))
  call_parsed = call_parser.parse_program
  call_parser.diagnostics.should be_empty
  converter.arena = call_parsed.arena
  call = call_parsed.arena[call_parsed.roots.last].as(Adamas::Compiler::Frontend::CallNode)
  if expression
    converter.__test_infer_constructor_expression(call_parsed.roots.last, locals)
  else
    converter.__test_infer_restricted_constructor("RestrictedConstructor", call, locals, caller_type)
  end
end

describe "generic constructor inference from initializer restrictions" do
  it "extracts an inner parameter instead of binding the whole carrier" do
    infer_restricted_constructor("def initialize(carrier : RestrictionCarrier(T)); end",
      "RestrictedConstructor.new(carrier)", {"carrier" => "RestrictionCarrier(Int32)"}).should eq(["Int32"])
  end

  it "matches nested carrier structure recursively" do
    infer_restricted_constructor("def initialize(carrier : RestrictionCarrier(RestrictionCarrier(T))); end",
      "RestrictedConstructor.new(carrier)", {"carrier" => "RestrictionCarrier(RestrictionCarrier(Int32))"}).should eq(["Int32"])
  end

  it "binds declared formals independently of parameter order" do
    infer_restricted_constructor("def initialize(tag : U, carrier : RestrictionCarrier(T)); end",
      "RestrictedConstructor.new(tag, carrier)", {"tag" => "Int64", "carrier" => "RestrictionCarrier(Int32)"}, "T, U").should eq(["Int32", "Int64"])
  end

  it "maps a bare-splat named-only boundary to named arguments" do
    infer_restricted_constructor("def initialize(*, carrier : RestrictionCarrier(T)); end",
      "RestrictedConstructor.new(carrier: carrier)", {"carrier" => "RestrictionCarrier(Int32)"}).should eq(["Int32"])
  end

  it "does not borrow an ambient caller T" do
    infer_restricted_constructor("def initialize(carrier : RestrictionCarrier(T)); end",
      "RestrictedConstructor.new(carrier)", {"carrier" => "RestrictionCarrier(Int32)"}, caller_type: "String").should eq(["Int32"])
  end

  it "accepts unsigned values under an unrelated abstract Int restriction" do
    infer_restricted_constructor("def initialize(tag : Int, carrier : RestrictionCarrier(T)); end",
      "RestrictedConstructor.new(tag, carrier)", {"tag" => "UInt64", "carrier" => "RestrictionCarrier(Int32)"}).should eq(["Int32"])
  end

  it "permits an omitted default without binding it to a generic formal" do
    infer_restricted_constructor("def initialize(carrier : RestrictionCarrier(T), tag : Int32 = 0); end",
      "RestrictedConstructor.new(carrier)", {"carrier" => "RestrictionCarrier(Int32)"}).should eq(["Int32"])
  end

  it "maps multiple named arguments independently of their source order" do
    infer_restricted_constructor("def initialize(tag : U, carrier : RestrictionCarrier(T)); end",
      "RestrictedConstructor.new(carrier: carrier, tag: tag)", {"tag" => "Int64", "carrier" => "RestrictionCarrier(Int32)"}, "T, U").should eq(["Int32", "Int64"])
  end

  it "prefers a structural restriction over an unconstrained formal" do
    initializer = "def initialize(carrier : RestrictionCarrier(T)); end\ndef initialize(value : T); end"
    infer_restricted_constructor(initializer,
      "RestrictedConstructor.new(carrier)", {"carrier" => "RestrictionCarrier(Int32)"}).should eq(["Int32"])
  end

  it "does not let declaration order select the unconstrained formal" do
    initializer = "def initialize(value : T); end\ndef initialize(carrier : RestrictionCarrier(T)); end"
    infer_restricted_constructor(initializer,
      "RestrictedConstructor.new(carrier)", {"carrier" => "RestrictionCarrier(Int32)"}).should eq(["Int32"])
  end

  it "compares nested structural restrictions recursively" do
    initializer = "def initialize(carrier : RestrictionCarrier(T)); end\ndef initialize(carrier : RestrictionCarrier(RestrictionCarrier(T))); end"
    infer_restricted_constructor(initializer,
      "RestrictedConstructor.new(carrier)", {"carrier" => "RestrictionCarrier(RestrictionCarrier(Int32))"}).should eq(["Int32"])
  end

  it "rejects conflicting repeated bindings instead of falling back by position" do
    expect_raises(ArgumentError, "cannot infer RestrictedConstructor type arguments from initializer restrictions") do
      infer_restricted_constructor("def initialize(left : RestrictionCarrier(T), right : RestrictionCarrier(T)); end",
        "RestrictedConstructor.new(left, right)", {"left" => "RestrictionCarrier(Int32)", "right" => "RestrictionCarrier(Int64)"})
    end
  end
end

describe "preliminary constructor expression inference" do
  it "extracts the same inner formal as strict lowering" do
    infer_restricted_constructor("def initialize(carrier : RestrictionCarrier(T)); end",
      "RestrictedConstructor.new(carrier)", {"carrier" => "RestrictionCarrier(Int32)"}, expression: true).should eq("RestrictedConstructor(Int32)")
  end

  it "infers multiple callee formals in restriction order" do
    infer_restricted_constructor("def initialize(tag : U, carrier : RestrictionCarrier(T)); end",
      "RestrictedConstructor.new(tag, carrier)", {"tag" => "Int64", "carrier" => "RestrictionCarrier(Int32)"}, "T, U", expression: true).should eq("RestrictedConstructor(Int32, Int64)")
  end

  it "defers an unresolved call without caching a positional carrier guess" do
    infer_restricted_constructor("def initialize(carrier : RestrictionCarrier(T)); end",
      "RestrictedConstructor.new(unknown)", {} of String => String, expression: true).should be_nil
  end
end
